data "aws_caller_identity" "current" {}

# ARN montado a partir da conta corrente: cada sessao do AWS Academy pode ser uma conta diferente,
# e iam:GetRole e bloqueado, entao nao da para usar data "aws_iam_role".
locals {
  lab_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/LabRole"
}

# Recursos nativos em vez do modulo terraform-aws-modules/eks: o modulo le sempre
# data "aws_iam_session_context", que chama iam:GetRole na role voclabs — bloqueado
# por deny explicito no AWS Academy, sem variavel para desligar.
resource "aws_eks_cluster" "this" {
  name     = "${var.project_name}-eks"
  version  = var.eks_cluster_version
  role_arn = local.lab_role_arn

  vpc_config {
    subnet_ids              = module.vpc.private_subnets
    endpoint_public_access  = true
    endpoint_private_access = true
  }

  # O proprio EKS concede admin a quem criou o cluster (a role voclabs), sem precisar
  # de iam:GetRole. E essa permissao que deixa o kubectl do pipeline da aplicacao operar.
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }
}

# vpc-cni e kube-proxy antes dos nodes: sem CNI os nodes nao ficam Ready.
resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_create = "OVERWRITE"
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
  node_role_arn   = local.lab_role_arn
  subnet_ids      = module.vpc.private_subnets

  # A partir do Kubernetes 1.33 o EKS nao publica mais AMI Amazon Linux 2.
  ami_type       = "AL2023_x86_64_STANDARD"
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
