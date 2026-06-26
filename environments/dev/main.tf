terraform {
  required_version = ">= 1.10.0"
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 5.0" }
    random = { source = "hashicorp/random", version = "~> 3.0" }
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      Owner       = var.owner
      ManagedBy   = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ── Security (KMS, Secrets Manager, S3, CloudTrail) ──────────────────────────
module "security" {
  source                       = "../../modules/security"
  project                      = var.project
  environment                  = var.environment
  owner                        = var.owner
  region                       = var.region
  account_id                   = var.account_id
  db_password                  = module.rds.db_password
  ses_sender_email             = var.ses_sender_email
  namespace                    = var.namespace
  rag_processing_queue_url     = module.sqs.rag_processing_queue_url
  appointment_events_queue_url = module.sqs.appointment_events_queue_url
  rds_endpoint                 = module.rds.db_endpoint
  groq_api_key                 = var.groq_api_key
  depends_on                   = [module.sqs, module.rds]
}

# ── VPC ───────────────────────────────────────────────────────────────────────
module "vpc" {
  source       = "../../modules/vpc"
  project      = var.project
  environment  = var.environment
  owner        = var.owner
  vpc_cidr     = var.vpc_cidr
  azs          = var.azs
  cluster_name = var.cluster_name
}

# ── EKS ──────────────────────────────────────────────────────────────────────
module "eks" {
  source             = "../../modules/eks"
  project            = var.project
  environment        = var.environment
  owner              = var.owner
  cluster_name       = var.cluster_name
  cluster_version    = var.cluster_version
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.private_app_subnet_ids
  node_instance_type = var.node_instance_type
  node_min_size      = var.node_min_size
  node_max_size      = var.node_max_size
  node_desired_size  = var.node_desired_size
  kms_key_arn        = module.security.kms_key_arn
}

# ── ECR ───────────────────────────────────────────────────────────────────────
module "ecr" {
  source      = "../../modules/ecr"
  project     = var.project
  environment = var.environment
  owner       = var.owner
  kms_key_arn = module.security.kms_key_arn
}

# ── RDS ───────────────────────────────────────────────────────────────────────
module "rds" {
  source         = "../../modules/rds"
  project        = var.project
  environment    = var.environment
  owner          = var.owner
  vpc_id         = module.vpc.vpc_id
  subnet_ids     = module.vpc.private_db_subnet_ids
  eks_node_sg_id = module.eks.node_security_group_id
  kms_key_arn    = module.security.kms_key_arn
  instance_class = var.rds_instance_class
  multi_az       = var.rds_multi_az
}

# ── Monitoring (CloudWatch + alarms + Lambdas) ────────────────────────────────
module "monitoring" {
  source                       = "../../modules/monitoring"
  project                      = var.project
  environment                  = var.environment
  owner                        = var.owner
  region                       = var.region
  account_id                   = var.account_id
  kms_key_arn                  = module.security.kms_key_arn
  rag_processing_dlq_arn       = module.sqs.rag_processing_dlq_arn
  rag_processing_dlq_name      = "${var.project}-${var.environment}-rag-processing-dlq"
  appointment_events_dlq_arn   = module.sqs.appointment_events_dlq_arn
  appointment_events_dlq_name  = "${var.project}-${var.environment}-appointment-events-dlq"
  appointment_events_queue_arn = module.sqs.appointment_events_queue_arn
  ops_email                    = var.ops_email
  ses_sender_email             = var.ses_sender_email
  oidc_provider_arn            = module.eks.oidc_provider_arn
  oidc_provider                = module.eks.oidc_provider
}

# ── SQS ───────────────────────────────────────────────────────────────────────
module "sqs" {
  source          = "../../modules/sqs"
  project         = var.project
  environment     = var.environment
  owner           = var.owner
  kms_key_arn     = module.security.kms_key_arn
  lambda_role_arn = module.monitoring.lambda_notification_role_arn
}

# ── IRSA ─────────────────────────────────────────────────────────────────────
module "irsa" {
  source                       = "../../modules/irsa"
  project                      = var.project
  environment                  = var.environment
  owner                        = var.owner
  namespace                    = var.namespace
  oidc_provider                = module.eks.oidc_provider
  oidc_provider_arn            = module.eks.oidc_provider_arn
  kms_key_arn                  = module.security.kms_key_arn
  region                       = var.region
  account_id                   = var.account_id
  db_credentials_secret_arn    = module.security.db_credentials_secret_arn
  jwt_private_key_secret_arn   = module.security.jwt_private_key_secret_arn
  jwt_public_key_secret_arn    = module.security.jwt_public_key_secret_arn
  groq_api_key_secret_arn      = module.security.groq_api_key_secret_arn
  ssm_parameter_prefix         = module.security.ssm_parameter_prefix
  documents_bucket_arn         = module.security.documents_bucket_arn
  rag_processing_queue_arn     = module.sqs.rag_processing_queue_arn
  rag_processing_dlq_arn       = module.sqs.rag_processing_dlq_arn
  appointment_events_queue_arn = module.sqs.appointment_events_queue_arn
  github_org                   = var.github_org
  github_repo                  = var.github_repo
}
