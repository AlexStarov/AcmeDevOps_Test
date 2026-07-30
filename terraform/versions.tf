terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  backend "s3" {
    bucket         = "acme-terraform-state"
    key            = "cell-01/terraform.tfstate"
    region         = "eu-central-1"
    encrypt        = true
    dynamodb_table = "acme-terraform-locks"
  }
}
