output "endpoint" {
  description = "Host:porta do PostgreSQL (acessível apenas de dentro da VPC)."
  value       = aws_db_instance.postgres.endpoint
}

output "databases" {
  description = "Database de cada ambiente."
  value = {
    homolog    = "gearup_homolog"
    production = aws_db_instance.postgres.db_name
  }
}

output "parametros_ssm" {
  description = "Parâmetros do SSM com os dados de conexão."
  value       = concat([for p in aws_ssm_parameter.conexao : p.name], [aws_ssm_parameter.senha.name])
}

output "comando_ler_senha" {
  description = "Lê a senha master (requer credenciais do lab)."
  value       = "aws ssm get-parameter --name ${aws_ssm_parameter.senha.name} --with-decryption --query Parameter.Value --output text"
}
