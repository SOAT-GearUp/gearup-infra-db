# ---------------------------------------------------------------------------
# Variáveis de entrada — defaults = menor custo que atende o Tech Challenge.
# ---------------------------------------------------------------------------

variable "nome_projeto" {
  description = "Prefixo dos recursos. Deve ser igual ao do gearup-infra-k8s (a VPC é procurada por \"<nome_projeto>-vpc\")."
  type        = string
  default     = "gearup"
}

variable "tags_padrao" {
  description = "Tags aplicadas a todos os recursos."
  type        = map(string)
  default = {
    Projeto     = "GearUp"
    Fase        = "3"
    Repositorio = "gearup-infra-db"
    ManagedBy   = "Terraform"
  }
}

variable "versao_postgres" {
  description = "Versão major do PostgreSQL (a AWS aplica o minor mais recente). Também define a família do parameter group."
  type        = string
  default     = "17"
}

variable "classe_instancia" {
  description = "Classe da instância. db.t3.micro ~ US$ 0,018/h single-AZ. O Learner Lab aceita de micro a medium."
  type        = string
  default     = "db.t3.micro"

  validation {
    condition     = can(regex("^db[.][a-z0-9]+[.](micro|small|medium)$", var.classe_instancia))
    error_message = "Use uma classe micro, small ou medium (limite do Learner Lab e do orçamento)."
  }
}

variable "armazenamento_gb" {
  description = "Armazenamento alocado em GB (mínimo 20 para gp3; máx. 100 no lab)."
  type        = number
  default     = 20

  validation {
    condition     = var.armazenamento_gb >= 20 && var.armazenamento_gb <= 100
    error_message = "Use entre 20 e 100 GB."
  }
}

variable "usuario_master" {
  description = "Usuário master do RDS."
  type        = string
  default     = "gearup"
}

variable "dias_backup" {
  description = "Retenção dos backups automáticos (0 desliga)."
  type        = number
  default     = 1
}
