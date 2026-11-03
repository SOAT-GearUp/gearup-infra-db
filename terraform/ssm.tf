# ---------------------------------------------------------------------------
# Credenciais publicadas no SSM Parameter Store, por ambiente
#
#   /gearup/<ambiente>/banco/{host,porta,usuario,senha}
#
# Fonte única dos dados de conexão para quem consome o banco:
#   - pipeline do gearup-api (monta o Secret do Kubernetes da API);
#   - Terraform do gearup-lambda-auth (injeta nas variáveis da Lambda).
#
# Cada ambiente lê apenas os próprios parâmetros, então a API e a Lambda de
# homologação nunca recebem o endereço nem a senha do banco de produção.
# A senha nunca passa por GitHub Secrets nem por arquivos versionados, e é
# gerada aqui (random_password) em vez de escolhida por uma pessoa.
# Parâmetros Standard do SSM não têm custo. SecureString usa a chave KMS
# gerenciada pela AWS (aws/ssm), também sem custo.
# ---------------------------------------------------------------------------

locals {
  parametros = merge([
    for ambiente, instancia in aws_db_instance.postgres : {
      "${ambiente}/host"    = instancia.address
      "${ambiente}/porta"   = tostring(instancia.port)
      "${ambiente}/usuario" = instancia.username
    }
  ]...)
}

resource "aws_ssm_parameter" "conexao" {
  for_each = local.parametros

  name  = "/${var.nome_projeto}/${split("/", each.key)[0]}/banco/${split("/", each.key)[1]}"
  type  = "String"
  value = each.value
}

resource "aws_ssm_parameter" "senha" {
  for_each = var.ambientes

  name  = "/${var.nome_projeto}/${each.key}/banco/senha"
  type  = "SecureString"
  value = random_password.master[each.key].result
}
