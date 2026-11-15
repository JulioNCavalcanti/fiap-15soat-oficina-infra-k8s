data "aws_caller_identity" "current" {}

locals {
  conta = data.aws_caller_identity.current.account_id

  # Namespace e ServiceAccounts dos manifestos: precisam bater com os nomes abaixo,
  # senao o pod nao recebe as credenciais do EKS Pod Identity.
  namespace_servicos = "oficina"

  fila_arn = { for nome, fila in aws_sqs_queue.saga : nome => fila.arn }

  # Cada servico consome a propria fila e publica nas que o orquestrador ou ele usam.
  servicos = {
    os = {
      consome = ["os-saga-eventos"]
      publica = ["billing-comandos", "execucao-comandos"]
    }
    execucao = {
      consome = ["execucao-comandos"]
      publica = ["os-saga-eventos"]
    }
    billing = {
      consome = ["billing-comandos"]
      publica = ["os-saga-eventos"]
    }
  }

  # A tabela fica em infra-db; o nome e contrato entre os repositorios.
  tabela_billing_arn = "arn:aws:dynamodb:${var.aws_region}:${local.conta}:table/${var.project_name}-billing"
}

# --- Cluster e nodes -------------------------------------------------------------------------

resource "aws_iam_role" "eks_cluster" {
  name = "${var.project_name}-eks-cluster"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role" "eks_node" {
  name = "${var.project_name}-eks-node"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_node" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
  ])
  role       = aws_iam_role.eks_node.name
  policy_arn = each.value
}

# --- Uma role por servico (EKS Pod Identity) ------------------------------------------------
# O SDK da AWS dos servicos (>= 2.21.30) le as credenciais do Pod Identity pela cadeia padrao,
# sem access key em Secret.

resource "aws_iam_role" "servico" {
  for_each = local.servicos
  name     = "${var.project_name}-${each.key}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_iam_role_policy" "servico_filas" {
  for_each = local.servicos
  name     = "filas-saga"
  role     = aws_iam_role.servico[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Consumir"
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:ChangeMessageVisibility",
          "sqs:GetQueueUrl",
          "sqs:GetQueueAttributes",
        ]
        Resource = [for f in each.value.consome : local.fila_arn[f]]
      },
      {
        Sid      = "Publicar"
        Effect   = "Allow"
        Action   = ["sqs:SendMessage", "sqs:GetQueueUrl", "sqs:GetQueueAttributes"]
        Resource = [for f in each.value.publica : local.fila_arn[f]]
      },
    ]
  })
}

resource "aws_iam_role_policy" "billing_dynamodb" {
  name = "tabela-billing"
  role = aws_iam_role.servico["billing"].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:DescribeTable",
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem",
        "dynamodb:Query",
        "dynamodb:Scan",
        "dynamodb:BatchGetItem",
        "dynamodb:BatchWriteItem",
        "dynamodb:TransactWriteItems",
        "dynamodb:TransactGetItems",
        "dynamodb:ConditionCheckItem",
      ]
      Resource = [local.tabela_billing_arn, "${local.tabela_billing_arn}/index/*"]
    }]
  })
}

resource "aws_eks_pod_identity_association" "servico" {
  for_each        = local.servicos
  cluster_name    = aws_eks_cluster.this.name
  namespace       = local.namespace_servicos
  service_account = "oficina-${each.key}"
  role_arn        = aws_iam_role.servico[each.key].arn
}
