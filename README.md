# Infraestrutura Kubernetes — Oficina Mecânica

> Tech Challenge — FIAP SOAT Fase 3
> Terraform · AWS · EKS

Provisiona a rede e o cluster onde a aplicação [`fiap-15soat-oficina-api`](https://github.com/KauaAlmeidaSilveira/fiap-15soat-oficina-api)
roda, mais o registro de imagens que o pipeline dela publica.

## O que este repositório cria

| Arquivo | Recursos |
|---|---|
| `vpc.tf` | VPC, subnets públicas e privadas em 2 AZs, NAT gateway único |
| `eks.tf` | Cluster EKS, node group gerenciado, addons (coredns, kube-proxy, vpc-cni, metrics-server) |
| `ecr.tf` | Repositório de imagens com scan on push e retenção das 10 mais recentes |

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
- Módulo oficial `terraform-aws-modules/vpc`; EKS com recursos nativos do provider (ver AWS Academy abaixo)
- Backend de state em S3 com lock em DynamoDB

## Pré-requisitos

- Credenciais AWS configuradas (`aws configure` ou as três variáveis de ambiente)
- Bucket `fiap-15soat-oficina-tfstate` e tabela DynamoDB `fiap-15soat-oficina-tflock` já criados

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
| `eks_cluster_name` | GitHub Secret `EKS_CLUSTER_NAME` da aplicação |
| `ecr_repository_url` | GitHub Secret `ECR_REPOSITORY_URL` da aplicação |
| `configure_kubectl_command` | aponta seu `kubectl` local para o cluster |
| `vpc_id`, `private_subnets`, `private_subnet_cidrs` | inspeção; o repo de banco descobre a VPC sozinho |

## Contrato com o repositório de banco

`project_name` **precisa ser idêntico** nos dois repositórios. É por esse nome que o
`fiap-15soat-oficina-infra-db` encontra a VPC (`${project_name}-vpc`), e é ele que compõe a tag
`kubernetes.io/cluster/${project_name}-eks` das subnets, exigida pelo EKS para descoberta de
load balancers e nodes. Divergir quebra silenciosamente.

Os dois repositórios são independentes: o de banco usa data source, não lê este state.

## Observações sobre o AWS Academy

O ambiente bloqueia `iam:CreateRole`, `iam:GetRole` e `iam:CreateOpenIDConnectProvider`. Por isso
o cluster e o node group reutilizam a `LabRole` pré-existente, com o ARN montado a partir da conta
corrente (`aws_caller_identity`) — cada sessão do Academy pode cair em uma conta diferente.

O EKS usa `aws_eks_cluster`/`aws_eks_node_group`/`aws_eks_addon` direto, sem o módulo
`terraform-aws-modules/eks`: o módulo sempre lê `aws_iam_session_context`, que chama `iam:GetRole`
e não pode ser desligado. O acesso de admin ao cluster vem de
`bootstrap_cluster_creator_admin_permissions`, concedido pelo próprio EKS à role que criou o cluster.

## CI/CD

Workflow em `.github/workflows/terraform.yml`:

| Evento | O que roda |
|---|---|
| Pull request | `fmt -check`, `validate`, `plan` — o plano é comentado no próprio PR |
| Push em `main` | `apply` |
| Manual (`workflow_dispatch`) | `apply` |

O job de validação roda **sem backend**, então não precisa de credencial: um PR continua sendo
verificado mesmo com as credenciais do AWS Academy expiradas.

O `apply` está atrelado ao Environment `producao`. Configure nele um revisor obrigatório
(Settings → Environments) para exigir aprovação humana antes de qualquer mudança.

### Secrets necessários

| Secret | Origem |
|---|---|
| `AWS_ACCESS_KEY_ID` | painel do AWS Academy |
| `AWS_SECRET_ACCESS_KEY` | painel do AWS Academy |
| `AWS_SESSION_TOKEN` | painel do AWS Academy — credenciais temporárias, expiram em poucas horas |

Um `concurrency group` impede duas execuções simultâneas, que disputariam o lock do DynamoDB.

## Custo

EKS (~US$0,10/hora de control plane), instâncias EC2 dos nodes, NAT gateway e ECR geram custo
enquanto estiverem no ar. Rode `terraform destroy` quando não precisar mais do ambiente.
