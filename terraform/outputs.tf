output "endpoints" {
  description = "Host:porta do PostgreSQL de cada ambiente (acessíveis apenas de dentro da VPC)."
  value       = { for ambiente, instancia in aws_db_instance.postgres : ambiente => instancia.endpoint }
}

output "databases" {
  description = "Database de cada ambiente."
  value       = { for ambiente, instancia in aws_db_instance.postgres : ambiente => instancia.db_name }
}

output "parametros_ssm" {
  description = "Parâmetros do SSM com os dados de conexão."
  value       = sort(concat([for p in aws_ssm_parameter.conexao : p.name], [for p in aws_ssm_parameter.senha : p.name]))
}

output "comando_ler_senha" {
  description = "Lê a senha master de cada ambiente (requer credenciais do lab)."
  value       = { for ambiente, p in aws_ssm_parameter.senha : ambiente => "aws ssm get-parameter --name ${p.name} --with-decryption --query Parameter.Value --output text" }
}
