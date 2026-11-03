# ---------------------------------------------------------------------------
# PostgreSQL gerenciado (Amazon RDS)
#
# Uma instância por ambiente (var.ambientes): homologação usa dados
# fictícios e produção os dados reais, sem compartilhar servidor. O schema de
# cada uma é criado pelas migrations do EF Core na primeira subida da API.
# Rede, security group e parameter group são compartilhados (não têm custo).
#
# CUSTO por instância: db.t3.micro single-AZ ~ US$ 0,018/h + 20 GB gp3
# ~ US$ 0,08/dia. Duas instâncias ~ US$ 0,04/h (ver RFC-002 no gearup-api).
# ATENÇÃO: o RDS continua cobrando com a sessão do lab encerrada. Rode o
# workflow de destroy ao fim de cada sessão.
# ---------------------------------------------------------------------------

resource "random_password" "master" {
  for_each = var.ambientes

  length  = 32
  special = true
  # Sem caracteres que quebram connection strings (; = ' " @ / \ :).
  override_special = "_-!#%*+"
}

resource "aws_db_subnet_group" "postgres" {
  name       = "${var.nome_projeto}-db-subnets"
  subnet_ids = data.aws_subnets.privadas.ids

  tags = {
    Name = "${var.nome_projeto}-db-subnets"
  }
}

resource "aws_security_group" "postgres" {
  name        = "${var.nome_projeto}-rds-sg"
  description = "PostgreSQL acessivel apenas de dentro da VPC da plataforma"
  vpc_id      = data.aws_vpc.plataforma.id

  tags = {
    Name = "${var.nome_projeto}-rds-sg"
  }
}

# Libera 5432 para o CIDR da VPC: cobre pods do EKS (subnets públicas) e a
# Lambda (subnets privadas) sem acoplar este repo aos security groups que os
# outros repos criam. Nada fora da VPC alcança o banco: as subnets privadas
# não têm rota para a internet e `publicly_accessible = false`.
resource "aws_vpc_security_group_ingress_rule" "postgres_vpc" {
  security_group_id = aws_security_group.postgres.id
  cidr_ipv4         = data.aws_vpc.plataforma.cidr_block
  ip_protocol       = "tcp"
  from_port         = 5432
  to_port           = 5432
  description       = "PostgreSQL a partir da VPC (EKS e Lambda)"
}

resource "aws_vpc_security_group_egress_rule" "postgres_saida" {
  security_group_id = aws_security_group.postgres.id
  cidr_ipv4         = data.aws_vpc.plataforma.cidr_block
  ip_protocol       = "-1"
  description       = "Saida restrita a VPC"
}

# Parâmetros voltados a consistência e diagnóstico de performance.
resource "aws_db_parameter_group" "postgres" {
  name   = "${var.nome_projeto}-postgres${var.versao_postgres}"
  family = "postgres${var.versao_postgres}"

  # Conexões sem TLS são recusadas (Lambda e API usam SSL Mode=Require).
  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  # Registra consultas acima de 500 ms: base para achar índices faltando.
  parameter {
    name  = "log_min_duration_statement"
    value = "500"
  }

  # Mata transações esquecidas abertas (evita locks longos e bloat).
  parameter {
    name  = "idle_in_transaction_session_timeout"
    value = "60000"
  }

  # Estatísticas por consulta (pg_stat_statements) para análise de gargalos.
  parameter {
    name         = "shared_preload_libraries"
    value        = "pg_stat_statements"
    apply_method = "pending-reboot"
  }
}

resource "aws_db_instance" "postgres" {
  for_each = var.ambientes

  # Produção mantém o identificador original (instância criada antes da
  # separação por ambiente); as demais recebem o sufixo do ambiente.
  identifier = each.key == "production" ? "${var.nome_projeto}-postgres" : "${var.nome_projeto}-postgres-${each.key}"

  engine                      = "postgres"
  engine_version              = var.versao_postgres
  auto_minor_version_upgrade  = true
  allow_major_version_upgrade = false

  instance_class    = var.classe_instancia
  allocated_storage = var.armazenamento_gb
  storage_type      = "gp3"
  storage_encrypted = true
  # `max_allocated_storage` omitido: autoscaling de storage é custo surpresa.

  db_name  = "gearup_${each.key}"
  username = var.usuario_master
  password = random_password.master[each.key].result
  port     = 5432

  db_subnet_group_name   = aws_db_subnet_group.postgres.name
  vpc_security_group_ids = [aws_security_group.postgres.id]
  parameter_group_name   = aws_db_parameter_group.postgres.name
  publicly_accessible    = false
  multi_az               = false # Multi-AZ dobraria o custo; ver RFC-002

  # 1 dia de backup automático: o armazenamento de backup até o tamanho do
  # banco é gratuito e permite point-in-time recovery.
  backup_retention_period  = var.dias_backup
  backup_window            = "06:00-07:00"
  maintenance_window       = "sun:07:30-sun:08:30"
  skip_final_snapshot      = true
  delete_automated_backups = true
  deletion_protection      = false
  copy_tags_to_snapshot    = true

  performance_insights_enabled = false
  apply_immediately            = true

  tags = {
    Name     = each.key == "production" ? "${var.nome_projeto}-postgres" : "${var.nome_projeto}-postgres-${each.key}"
    Ambiente = each.key
  }
}

# A instância e a senha de produção já existiam antes do for_each: os blocos
# moved evitam que o Terraform as destrua e recrie.
moved {
  from = aws_db_instance.postgres
  to   = aws_db_instance.postgres["production"]
}

moved {
  from = random_password.master
  to   = random_password.master["production"]
}
