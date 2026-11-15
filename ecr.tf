# Um repositorio por servico. force_delete: o ambiente e destruido depois de cada uso, e o
# destroy falharia com imagens dentro do repositorio.
locals {
  repositorios = toset(["os", "execucao", "billing"])
}

resource "aws_ecr_repository" "servico" {
  for_each             = local.repositorios
  name                 = "${var.project_name}-${each.key}"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "servico" {
  for_each   = local.repositorios
  repository = aws_ecr_repository.servico[each.key].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Manter apenas as 10 imagens mais recentes"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
