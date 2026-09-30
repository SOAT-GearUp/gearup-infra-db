# ---------------------------------------------------------------------------
# Credenciais publicadas no SSM Parameter Store
#
# Fonte única dos dados de conexão para quem consome o banco:
#   - pipeline do gearup-api (monta o Secret do Kubernetes da API);
#   - Terraform do gearup-lambda-auth (injeta nas variáveis da Lambda).
#
# Assim a senha nunca passa por GitHub Secrets nem por arquivos versionados,
# e é gerada aqui (random_password) em vez de escolhida por uma pessoa.
# Parâmetros Standard do SSM não têm custo. SecureString usa a chave KMS
# gerenciada pela AWS (aws/ssm), também sem custo.
# ---------------------------------------------------------------------------

locals {
  prefixo_ssm = "/${var.nome_projeto}/banco"

  parametros = {
    host    = aws_db_instance.postgres.address
    porta   = tostring(aws_db_instance.postgres.port)
    usuario = aws_db_instance.postgres.username
  }
}

resource "aws_ssm_parameter" "conexao" {
  for_each = local.parametros

  name  = "${local.prefixo_ssm}/${each.key}"
  type  = "String"
  value = each.value
}

resource "aws_ssm_parameter" "senha" {
  name  = "${local.prefixo_ssm}/senha"
  type  = "SecureString"
  value = random_password.master.result
}
