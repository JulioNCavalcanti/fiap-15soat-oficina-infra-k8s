terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }

  # Backend remoto: sem ele, cada execucao do pipeline comecaria com state vazio
  # e tentaria recriar a infraestrutura inteira.
  # O bucket e a tabela de lock sao criados uma unica vez, fora do Terraform.
  backend "s3" {
    bucket         = "fiap-15soat-oficina-tfstate"
    key            = "infra-k8s/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "fiap-15soat-oficina-tflock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
}
