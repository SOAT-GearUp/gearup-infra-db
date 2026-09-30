# ---------------------------------------------------------------------------
# Versões e backend do state
#
# Mesmo bucket dos demais repositórios (gearup-tfstate-<account_id>, criado
# por scripts/tf-init.sh), chave própria. Lock nativo do S3, sem DynamoDB.
# ---------------------------------------------------------------------------
terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  backend "s3" {
    key          = "infra-db/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

# Região fixa: o Learner Lab só libera us-east-1 e us-west-2.
provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = var.tags_padrao
  }
}
