# ---------------------------------------------------------------------------
# Rede (provisionada pelo repositório gearup-infra-k8s)
#
# A VPC e as subnets são encontradas por tags, sem ler o state do outro
# repositório: os dois ciclos de vida ficam independentes e basta que a VPC
# exista. Ordem de deploy: gearup-infra-k8s -> gearup-infra-db.
# ---------------------------------------------------------------------------

data "aws_vpc" "plataforma" {
  tags = {
    Name = "${var.nome_projeto}-vpc"
  }
}

# Subnets privadas: sem rota para a internet. O banco só é alcançável de
# dentro da VPC (pods do EKS e Lambda de autenticação).
data "aws_subnets" "privadas" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.plataforma.id]
  }

  tags = {
    Camada = "privada"
  }
}
