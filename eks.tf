# Recursos nativos em vez do modulo terraform-aws-modules/eks (heranca da Fase 3, no AWS Academy).
# As roles do cluster, dos nodes e de cada servico ficam em iam.tf.
resource "aws_eks_cluster" "this" {
  name     = "${var.project_name}-eks"
  version  = var.eks_cluster_version
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    subnet_ids              = module.vpc.private_subnets
    endpoint_public_access  = true
    endpoint_private_access = true
  }

  # O proprio EKS concede admin a quem criou o cluster: e essa permissao que deixa o kubectl
  # de quem rodou o apply operar o cluster.
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  depends_on = [aws_iam_role_policy_attachment.eks_cluster]
}

# vpc-cni e kube-proxy antes dos nodes: sem CNI os nodes nao ficam Ready.
# Prefix delegation: cada ENI recebe blocos /28 em vez de IPs avulsos. Sem isso, uma instancia
# medium aceita so 8 pods, contando os do sistema; com ele, o node group calcula ate 110.
resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  configuration_values = jsonencode({
    env = {
      ENABLE_PREFIX_DELEGATION = "true"
      WARM_PREFIX_TARGET       = "1"
    }
  })
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_create = "OVERWRITE"
}

# Sem launch template o node group usa o security group gerenciado do cluster, que ja
# libera todo o trafego entre control plane e nodes — inclusive a porta 10251 do
# metrics-server, que exigia regra extra no modulo.
resource "aws_eks_node_group" "default" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "default"
  node_role_arn   = aws_iam_role.eks_node.arn
  subnet_ids      = module.vpc.private_subnets

  # A partir do Kubernetes 1.33 o EKS nao publica mais AMI Amazon Linux 2.
  ami_type       = var.node_ami_type
  instance_types = [var.node_instance_type]

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  depends_on = [
    aws_eks_addon.vpc_cni,
    aws_eks_addon.kube_proxy,
    aws_iam_role_policy_attachment.eks_node,
  ]
}

# coredns e metrics-server sao Deployments: so ficam ACTIVE com nodes para agendar.
resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"

  depends_on = [aws_eks_node_group.default]
}

resource "aws_eks_addon" "metrics_server" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "metrics-server"
  resolve_conflicts_on_create = "OVERWRITE"

  depends_on = [aws_eks_node_group.default]
}

# Agente que entrega aos pods as credenciais das roles de servico (iam.tf).
resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "eks-pod-identity-agent"
  resolve_conflicts_on_create = "OVERWRITE"

  depends_on = [aws_eks_node_group.default]
}
