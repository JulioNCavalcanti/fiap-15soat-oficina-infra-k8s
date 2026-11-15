output "eks_cluster_name" {
  description = "Nome do cluster EKS — usar em `aws eks update-kubeconfig --name <valor>`"
  value       = aws_eks_cluster.this.name
}

output "eks_cluster_endpoint" {
  value = aws_eks_cluster.this.endpoint
}

output "ecr_repositorios" {
  description = "URI de cada repositorio de imagem, por servico — campo `image:` dos manifestos"
  value       = { for nome, repo in aws_ecr_repository.servico : nome => repo.repository_url }
}

output "roles_servicos" {
  description = "Role IAM de cada servico, entregue ao pod pelo EKS Pod Identity (namespace oficina, ServiceAccount oficina-<servico>)"
  value       = { for nome, role in aws_iam_role.servico : nome => role.arn }
}

output "configure_kubectl_command" {
  description = "Comando para configurar o kubectl local apontando para o cluster criado"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.this.name}"
}

# Outputs de rede: publicados para inspecao humana e para eventual uso futuro.
# O repo de banco NAO os consome via remote state — ele descobre a VPC por
# data source, o que evita dar a ele permissao de leitura neste state.
output "vpc_id" {
  description = "ID da VPC criada"
  value       = module.vpc.vpc_id
}

output "private_subnets" {
  description = "IDs das subnets privadas"
  value       = module.vpc.private_subnets
}

output "private_subnet_cidrs" {
  description = "CIDRs das subnets privadas — origem liberada no security group do RDS"
  value       = module.vpc.private_subnets_cidr_blocks
}

output "filas_saga" {
  description = "URLs das filas da Saga, por nome logico"
  value       = { for nome, fila in aws_sqs_queue.saga : nome => fila.url }
}
