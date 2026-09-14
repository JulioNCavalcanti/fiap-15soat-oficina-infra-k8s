output "eks_cluster_name" {
  description = "Nome do cluster EKS — usar em `aws eks update-kubeconfig --name <valor>`"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "ecr_repository_url" {
  description = "URI a usar no campo `image:` do deployment e no push do CI/CD da aplicacao"
  value       = aws_ecr_repository.oficina_api.repository_url
}

output "configure_kubectl_command" {
  description = "Comando para configurar o kubectl local apontando para o cluster criado"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
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
