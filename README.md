# Infraestrutura Kubernetes — Oficina Mecânica

> Tech Challenge — FIAP SOAT Fase 4
> Terraform · AWS · EKS · SQS

Provisiona a rede e o cluster onde rodam os 3 microsserviços da Fase 4 (OS, Execução e Billing), o
registro de imagens de cada um, as filas da Saga e as permissões IAM de cada serviço.

## O que este repositório cria

| Arquivo | Recursos |
|---|---|
| `vpc.tf` | VPC, subnets públicas e privadas em 2 AZs, NAT gateway único |
| `eks.tf` | Cluster EKS, node group gerenciado (ARM, `t4g.medium`), addons (coredns, kube-proxy, vpc-cni, metrics-server, eks-pod-identity-agent) |
| `iam.tf` | Roles do cluster e dos nodes; uma role por serviço, entregue ao pod pelo EKS Pod Identity |
| `ecr.tf` | Um repositório por serviço (`oficina-os`, `oficina-execucao`, `oficina-billing`), com scan on push, retenção das 10 mais recentes e `force_delete` |
| `sqs.tf` | Filas da Saga (`oficina-os-saga-eventos`, `oficina-billing-comandos`, `oficina-execucao-comandos`), cada uma com DLQ após 5 recebimentos |

O banco de dados **não** está aqui — fica em `fiap-15soat-oficina-infra-db`.

## Arquitetura

```
                    Internet
                       │
              ┌────────▼────────┐
              │  subnets        │  NAT gateway (saída dos pods)
              │  públicas       │
              └────────┬────────┘
                       │
   ┌───────────────────▼───────────────────┐
   │          subnets privadas             │
   │   ┌─────────────┐   ┌─────────────┐   │
   │   │ node EKS    │   │ node EKS    │   │  ← aplicação roda aqui
   │   └─────────────┘   └─────────────┘   │
   └───────────────────────────────────────┘
              VPC 10.0.0.0/16

   ECR  ←── imagens publicadas pelo CI/CD da aplicação
```

## Tecnologias

- Terraform >= 1.5, provider AWS ~> 5.60
- Módulo oficial `terraform-aws-modules/vpc`; EKS com recursos nativos do provider (ver "Permissões dos serviços")
- Backend de state em S3 com lock em DynamoDB

## Pré-requisitos

- Credenciais AWS configuradas (`aws configure` ou as três variáveis de ambiente)
- Bucket `fiap-15soat-oficina-fase4-tfstate` e tabela DynamoDB `fiap-15soat-oficina-tflock` já criados

## Como aplicar

```bash
terraform init
terraform plan
terraform apply     # ~15-20 min, o EKS demora para ficar pronto
```

Depois:

```bash
terraform output
```

| Output | Onde usar |
|---|---|
| `eks_cluster_name` | `aws eks update-kubeconfig` (o `scripts/deploy-aws.sh` do OS lê sozinho) |
| `ecr_repositorios` | URI da imagem de cada serviço (lido pelo `scripts/deploy-aws.sh` do OS) |
| `roles_servicos` | inspeção: role IAM de cada serviço |
| `filas_saga` | inspeção: URL de cada fila |
| `configure_kubectl_command` | aponta seu `kubectl` local para o cluster |
| `vpc_id`, `private_subnets`, `private_subnet_cidrs` | inspeção; o repo de banco descobre a VPC sozinho |

## Contrato com o repositório de banco

`project_name` **precisa ser idêntico** nos dois repositórios. É por esse nome que o
`fiap-15soat-oficina-infra-db` encontra a VPC (`${project_name}-vpc`), e é ele que compõe a tag
`kubernetes.io/cluster/${project_name}-eks` das subnets, exigida pelo EKS para descoberta de
load balancers e nodes. Divergir quebra silenciosamente.

Os dois repositórios são independentes: o de banco usa data source, não lê este state.

## Permissões dos serviços (EKS Pod Identity)

Cada serviço recebe uma role própria, sem access key em Secret: o addon `eks-pod-identity-agent`
entrega as credenciais ao pod da ServiceAccount `oficina-<servico>` no namespace `oficina`. Esses
nomes são contrato com os manifestos de `k8s/` de cada serviço.

| Role | Pode |
|---|---|
| `oficina-os` | consumir `os-saga-eventos`; publicar em `billing-comandos` e `execucao-comandos` |
| `oficina-execucao` | consumir `execucao-comandos`; publicar em `os-saga-eventos` |
| `oficina-billing` | consumir `billing-comandos`; publicar em `os-saga-eventos`; ler e gravar a tabela `oficina-billing` |

O EKS usa `aws_eks_cluster`/`aws_eks_node_group`/`aws_eks_addon` direto, sem o módulo
`terraform-aws-modules/eks` (herança da Fase 3, no AWS Academy). O acesso de admin ao cluster vem de
`bootstrap_cluster_creator_admin_permissions`, concedido a quem rodou o `apply`.

## CI/CD

O workflow `.github/workflows/terraform.yml` (plan em PR, apply em `main` com aprovação no Environment
`producao`) continua no repositório, mas o GitHub Actions da conta está bloqueado por billing. Na Fase 4
o `apply` e o `destroy` são manuais, pela conta AWS pessoal do Júlio, com os scripts do repositório do OS:
`scripts/aws-bootstrap.sh` (uma vez), `scripts/subir-aws.sh` e `scripts/destruir-aws.sh`.

## Custo

EKS (~US$0,10/hora de control plane), instâncias EC2 dos nodes, NAT gateway e ECR geram custo
enquanto estiverem no ar. O ambiente é destruído depois de cada uso (`scripts/destruir-aws.sh` do OS,
que apaga antes os NLBs criados pelo Kubernetes).
