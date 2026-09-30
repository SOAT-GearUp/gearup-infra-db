<#
.SYNOPSIS
    terraform init com backend S3 da propria conta (Windows PowerShell 5.1).

.DESCRIPTION
    Equivalente a scripts/tf-init.sh. Cria, se ainda nao existir, o bucket
    gearup-tfstate-<account_id> e inicializa o Terraform apontando para ele.

.EXAMPLE
    .\scripts\tf-init.ps1
    .\scripts\tf-init.ps1 -Diretorio datadog
#>
param(
    [string]$Diretorio = 'terraform'
)

$regiao = 'us-east-1'

$conta = aws sts get-caller-identity --query Account --output text
if ($LASTEXITCODE -ne 0) {
    Write-Host 'Credenciais AWS invalidas ou expiradas. Recopie o bloco de AWS Details -> AWS CLI no lab.' -ForegroundColor Red
    exit 1
}

$bucket = "gearup-tfstate-$conta"

aws s3api head-bucket --bucket $bucket 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Criando bucket de state $bucket..." -ForegroundColor Cyan
    aws s3api create-bucket --bucket $bucket --region $regiao | Out-Null
    aws s3api put-bucket-versioning --bucket $bucket --versioning-configuration Status=Enabled
    aws s3api put-public-access-block --bucket $bucket --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
    $criptografia = Join-Path $env:TEMP 'gearup-sse.json'
    Set-Content -Path $criptografia -Encoding ascii -Value '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
    aws s3api put-bucket-encryption --bucket $bucket --server-side-encryption-configuration "file://$criptografia"
}

terraform "-chdir=$Diretorio" init -input=false -reconfigure "-backend-config=bucket=$bucket"
