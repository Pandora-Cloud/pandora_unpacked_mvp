# terraform/main.tf
module "auth" {
  source       = "./modules/auth"
  project_name = var.project_name
}

module "compute" {
  source           = "./modules/compute"
  project_name     = var.project_name
  lambda_role_arn  = module.iam.lambda_exec_arn
  dynamodb_table   = module.storage.chat_history_table_name
  dlq_arn          = module.storage.dlq_arn
  user_pool_arn    = module.auth.user_pool_arn
  cert_arn         = module.networking.cert_arn
}

module "iam" {
  source           = "./modules/iam"
  project_name     = var.project_name
  region           = var.region
  dynamodb_table   = module.storage.chat_history_table_name
  dlq_arn          = module.storage.dlq_arn
  identity_pool_id = module.auth.identity_pool_id
}

module "monitoring" {
  source       = "./modules/monitoring"
  project_name = var.project_name
}

module "networking" {
  source            = "./modules/networking"
  api_domain_name   = module.compute.api_domain_name
  api_hosted_zone_id = module.compute.api_hosted_zone_id
  api_id            = module.compute.api_id
}

module "security" {
  source       = "./modules/security"
  project_name = var.project_name
  api_arn      = module.compute.api_arn
}

module "storage" {
  source           = "./modules/storage"
  project_name     = var.project_name
  kms_key_arn      = module.security.kms_key_arn
}
