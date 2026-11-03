# gearup-infra-db

Banco de dados gerenciado da plataforma **GearUp** (Tech Challenge FIAP — Fase 3): **Amazon RDS for PostgreSQL 17**, provisionado com Terraform.

## Propósito

- **Uma instância RDS PostgreSQL por ambiente** (`gearup-postgres-homolog` com dados fictícios, `gearup-postgres` com os dados de produção), em subnets privadas, criptografadas, com TLS obrigatório e backup automático.
- Parameter group ajustado para consistência e diagnóstico de performance.
- Senha master gerada pelo Terraform para cada instância e publicada, junto com os dados de conexão, no **SSM Parameter Store** em `/gearup/<ambiente>/banco/*` — fonte única para a API (pipeline do gearup-api) e para a Lambda de autenticação de cada ambiente.

A **instância** é responsabilidade deste repositório; o **schema** (tabelas, índices, constraints) evolui com o código, via migrations do EF Core no repositório [gearup-api](https://github.com/SOAT-GearUp/gearup-api). Justificativa da escolha do banco e modelagem completa (diagrama ER, relacionamentos, índices e constraints):

- [RFC-002 — Banco de dados gerenciado](https://github.com/SOAT-GearUp/gearup-api/blob/master/docs/fase-3/RFC/RFC-002%20-%20Banco%20de%20dados%20gerenciado.md)
- [Modelagem e Justificativa](https://github.com/SOAT-GearUp/gearup-api/blob/master/docs/fase-3/Banco%20de%20Dados/Modelagem%20e%20Justificativa.md)

## Arquitetura

```mermaid
flowchart LR
    subgraph VPC["gearup-vpc (criada por gearup-infra-k8s)"]
        subgraph PUB["subnets públicas"]
            PODS[Pods gearup-api<br/>EKS]
        end
        subgraph PRIV["subnets privadas — Camada=privada, sem rota p/ internet"]
            RDSH[(gearup-postgres-homolog<br/>db.t3.micro · 20 GB gp3<br/>gearup_homolog)]
            RDSP[(gearup-postgres<br/>db.t3.micro · 20 GB gp3<br/>gearup_production)]
            LBD[Lambda gearup-auth-cpf-&lt;amb&gt;]
        end
        SG{{SG gearup-rds-sg<br/>5432 somente do CIDR da VPC}}
    end
    PG[[Parameter group<br/>force_ssl · slow query 500ms<br/>idle tx timeout · pg_stat_statements]]
    SSM[(SSM /gearup/&lt;amb&gt;/banco/<br/>host · porta · usuario · senha🔒)]

    PODS -- TLS --> SG
    LBD -- TLS --> SG
    SG --> RDSH
    SG --> RDSP
    PG -.-> RDSH
    PG -.-> RDSP
    RDSH -. endpoint + senha .-> SSM
    RDSP -. endpoint + senha .-> SSM
```

```mermaid
erDiagram
    Clientes ||--o{ Veiculos : possui
    Clientes ||--o{ OrdensServico : solicita
    Veiculos ||--o{ OrdensServico : atendido
    OrdensServico ||--|{ HistoricoOrdensServico : registra
    OrdensServico ||--o{ Orcamentos : versiona
    Orcamentos ||--|{ ItensOrcamento : contem
    EstoqueItens ||--o{ MovimentacoesEstoque : movimenta
    OrdensServico ||--o{ Notificacoes : gera
    Clientes ||--o{ Notificacoes : recebe
    Clientes |o--o{ Usuarios : acessa
```

(Diagrama completo, com colunas e constraints, na documentação de modelagem.)

## Tecnologias

Terraform ≥ 1.10 (providers `aws` 6.x e `random` 3.x) · Amazon RDS for PostgreSQL · AWS SSM Parameter Store · GitHub Actions · state em S3 com lock nativo.

## Pré-requisito

A VPC do [gearup-infra-k8s](https://github.com/SOAT-GearUp/gearup-infra-k8s) já aplicada. Ela é encontrada pela tag `Name = gearup-vpc` e as subnets por `Camada = privada` — este repositório não lê o state do outro.

## CI/CD

Workflow [`terraform.yml`](.github/workflows/terraform.yml):

| Evento | O que roda | Ambiente GitHub |
|---|---|---|
| Pull Request | `fmt -check`, `validate`, `plan` | homolog |
| push `homolog` | `plan` contra a conta real | homolog |
| push `main` (só via PR) | `apply` | production |
| Run workflow → `apply` / `destroy` | manual | production |

Este repositório provisiona as instâncias **dos dois ambientes**: `homolog` valida com `plan` e só `main` aplica, para que nenhuma mudança de infraestrutura chegue à conta sem passar por PR ([RFC-002](https://github.com/SOAT-GearUp/gearup-api/blob/master/docs/fase-3/RFC/RFC-002%20-%20Banco%20de%20dados%20gerenciado.md)).

**Secrets:** `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN` (Learner Lab → AWS Details; expiram a cada sessão).

## Execução local

Windows PowerShell 5.1, credenciais do lab em `%USERPROFILE%\.aws\credentials`:

```powershell
.\scripts\tf-init.ps1
terraform -chdir=terraform plan
terraform -chdir=terraform apply        # ~8 min

# Conferir o que foi publicado para os consumidores
aws ssm get-parameters-by-path --path /gearup/homolog/banco --query "Parameters[].Name"
aws ssm get-parameters-by-path --path /gearup/production/banco --query "Parameters[].Name"
```

Bash: `bash scripts/tf-init.sh terraform`.

O banco **não é acessível de fora da VPC**. Para inspecionar dados, use um pod temporário no cluster:

```powershell
$senha = aws ssm get-parameter --name /gearup/homolog/banco/senha --with-decryption --query Parameter.Value --output text
$hostDb = aws ssm get-parameter --name /gearup/homolog/banco/host --query Parameter.Value --output text
kubectl run psql --rm -it --restart=Never --image=postgres:17-alpine --env="PGPASSWORD=$senha" -- psql "host=$hostDb dbname=gearup_homolog user=gearup sslmode=require"
```

## Contrato publicado no SSM

| Parâmetro | Tipo | Conteúdo |
|---|---|---|
Um conjunto por ambiente (`<amb>` = `homolog` ou `production`):

| Parâmetro | Tipo | Conteúdo |
|---|---|---|
| `/gearup/<amb>/banco/host` | String | endpoint do RDS do ambiente |
| `/gearup/<amb>/banco/porta` | String | 5432 |
| `/gearup/<amb>/banco/usuario` | String | usuário master |
| `/gearup/<amb>/banco/senha` | SecureString | senha gerada (32 caracteres) |

Consumidores: pipeline `CD` do gearup-api (monta o Secret do Kubernetes) e Terraform do gearup-lambda-auth (variáveis da Lambda). Cada ambiente lê só os próprios parâmetros.

## Destroy

Antes do `gearup-infra-k8s` e depois do gearup-api e do gearup-lambda-auth:

```powershell
terraform -chdir=terraform destroy
```

## Custos

Por instância: db.t3.micro single-AZ ~US$ 0,018/h + 20 GB gp3 ~US$ 0,08/dia. Duas instâncias: ~US$ 0,04/h. **O RDS cobra com o lab parado** — destrua ao fim da sessão.

## Swagger / Postman

Este repositório não expõe APIs. Ver [gearup-api](https://github.com/SOAT-GearUp/gearup-api#apis-swagger-e-postman).
