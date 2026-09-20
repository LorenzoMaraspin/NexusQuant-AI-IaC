terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # Uncomment to enable S3 remote state storage:
  # backend "s3" {
  #   bucket         = "nexusquant-terraform-state"
  #   key            = "live/terraform.tfstate"
  #   region         = "eu-north-1"
  #   dynamodb_table = "nexusquant-terraform-locks"
  #   encrypt        = true
  # }
}
