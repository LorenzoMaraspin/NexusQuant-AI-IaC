terraform {
  required_providers {
    postgresql = {
      source  = "cyrilgdn/postgresql"
      version = "~> 1.22"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
