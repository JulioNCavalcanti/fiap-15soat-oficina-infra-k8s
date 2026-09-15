variable "aws_region" {
  description = "Regiao AWS onde a infraestrutura e criada"
  type        = string
  default     = "us-east-1"
}

# ATENCAO: precisa ser identico em fiap-15soat-oficina-infra-db.
# As tags das subnets gravam "kubernetes.io/cluster/${project_name}-eks" por
# convencao de string, e o RDS descobre esta VPC pelo nome "${project_name}-vpc".
variable "project_name" {
  description = "Prefixo de nome de todos os recursos. Contrato compartilhado entre os repos de infraestrutura."
  type        = string
  default     = "oficina"
}

variable "vpc_cidr" {
  description = "Bloco CIDR da VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "AZs usadas pelas subnets"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "eks_cluster_version" {
  description = "Versao do Kubernetes no EKS"
  type        = string
  default     = "1.35"
}

variable "node_instance_type" {
  description = "Tipo de instancia EC2 dos nodes do EKS"
  type        = string
  default     = "t3.medium"
}

variable "node_desired_size" {
  description = "Quantidade desejada de nodes (a aplicacao escala pods via HPA nesses nodes, nao os nodes em si)"
  type        = number
  default     = 2
}

variable "node_min_size" {
  type    = number
  default = 1
}

variable "node_max_size" {
  type    = number
  default = 3
}
