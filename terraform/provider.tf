# terraform/provider.tf
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40.0"
    }
  }
  
  required_version = ">= 1.5, < 2.0"
  
  backend "s3" {
    bucket         = "chatbot-mvp-terraform-state"
    key            = "production/terraform.tfstate"
    region         = "us-west-2"
    encrypt        = true
    dynamodb_table = "chatbot-mvp-terraform-state-lock"
    profile        = "forge_interns_tf"
  }
}

provider "aws" {
  region  = var.region
  profile = var.profile
}
