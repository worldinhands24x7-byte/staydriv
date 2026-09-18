terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }

  # Production backend configuration (Uncomment to use S3 Remote State)
  # backend "s3" {
  #   bucket         = "staydriv-terraform-state-us-east-1"
  #   key            = "prod/us-east-1/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "staydriv-terraform-locks"
  #   encrypt        = true
  # }
}

provider "aws" {
  region              = var.aws_region
  allowed_account_ids = ["347234956877"]

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      Region      = var.aws_region
      ManagedBy   = "Terraform"
    }
  }
}
