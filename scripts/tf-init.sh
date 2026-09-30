#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# terraform init com backend S3 da própria conta.
#
# Uso:  scripts/tf-init.sh [diretorio]      (padrão: terraform)
#
# Cria, se ainda não existir, o bucket gearup-tfstate-<account_id> (versionado,
# criptografado e sem acesso público) e inicializa o Terraform apontando para
# ele. O mesmo bucket é compartilhado pelos repositórios de infra e da Lambda,
# cada um com a sua chave (definida no bloco backend de versions.tf).
#
# Custo: centavos por mês (alguns KB de state).
# ---------------------------------------------------------------------------
set -euo pipefail

DIRETORIO="${1:-terraform}"
REGIAO="us-east-1"

CONTA=$(aws sts get-caller-identity --query Account --output text)
BUCKET="gearup-tfstate-${CONTA}"

if ! aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  echo "Criando bucket de state $BUCKET..."
  aws s3api create-bucket --bucket "$BUCKET" --region "$REGIAO" >/dev/null
  aws s3api put-bucket-versioning --bucket "$BUCKET" \
    --versioning-configuration Status=Enabled
  aws s3api put-public-access-block --bucket "$BUCKET" \
    --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
  aws s3api put-bucket-encryption --bucket "$BUCKET" \
    --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
fi

terraform -chdir="$DIRETORIO" init -input=false -reconfigure -backend-config="bucket=${BUCKET}"
