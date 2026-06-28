terraform {
  required_version = ">= 1.10.0"
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 5.0" }
    random = { source = "hashicorp/random", version = "~> 3.0" }
    tls    = { source = "hashicorp/tls", version = "~> 4.0" }
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

# ── KMS Key (root-level to break module dependency cycles) ────────────────────
resource "aws_kms_key" "main" {
  description             = "${var.project} ${var.environment} — encryption key for RDS, S3, SQS, Secrets Manager"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  rotation_period_in_days = 365

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "RootFullAccess"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${var.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "CloudWatchLogs"
        Effect    = "Allow"
        Principal = { Service = "logs.${var.region}.amazonaws.com" }
        Action    = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey"]
        Resource  = "*"
      },
      {
        Sid       = "CloudTrail"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey"]
        Resource  = "*"
      }
    ]
  })
}

resource "aws_kms_alias" "main" {
  name          = "alias/${var.project}-${var.environment}-key"
  target_key_id = aws_kms_key.main.key_id
}

locals {
  kms_key_arn = aws_kms_key.main.arn
  ssm_prefix  = "/${var.project}/${var.environment}"
}

# ── Security (Secrets Manager, S3, CloudTrail, Bedrock, SES, SSM) ─────────────
module "security" {
  source           = "../../modules/security"
  project          = var.project
  environment      = var.environment
  owner            = var.owner
  region           = var.region
  account_id       = var.account_id
  kms_key_arn      = local.kms_key_arn
  ses_sender_email = var.ses_sender_email
  namespace        = var.namespace
  groq_api_key     = var.groq_api_key
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
  kms_key_arn        = local.kms_key_arn
}

# ── ECR ───────────────────────────────────────────────────────────────────────
module "ecr" {
  source      = "../../modules/ecr"
  project     = var.project
  environment = var.environment
  owner       = var.owner
  kms_key_arn = local.kms_key_arn
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
  kms_key_arn    = local.kms_key_arn
  instance_class = var.rds_instance_class
  multi_az       = var.rds_multi_az
}

# ── SQS ───────────────────────────────────────────────────────────────────────
module "sqs" {
  source      = "../../modules/sqs"
  project     = var.project
  environment = var.environment
  owner       = var.owner
  kms_key_arn = local.kms_key_arn
}

# ── Monitoring (CloudWatch + alarms + Lambda) ─────────────────────────────────
module "monitoring" {
  source                       = "../../modules/monitoring"
  project                      = var.project
  environment                  = var.environment
  owner                        = var.owner
  region                       = var.region
  account_id                   = var.account_id
  kms_key_arn                  = local.kms_key_arn
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

# ── SQS Lambda queue policy (root-level to break monitoring↔sqs cycle) ────────
resource "aws_sqs_queue_policy" "lambda_appointment" {
  queue_url = module.sqs.appointment_events_queue_id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { AWS = module.monitoring.lambda_notification_role_arn }
        Action    = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
        Resource  = module.sqs.appointment_events_queue_arn
      }
    ]
  })
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
  kms_key_arn                  = local.kms_key_arn
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
}

# ── Cross-module SSM Parameters (root-level to break security↔sqs/rds cycles) ─
resource "aws_ssm_parameter" "sqs_rag_queue_url" {
  name      = "${local.ssm_prefix}/sqs-rag-queue-url"
  type      = "String"
  value     = module.sqs.rag_processing_queue_url
  overwrite = true
}

resource "aws_ssm_parameter" "sqs_appointment_queue_url" {
  name      = "${local.ssm_prefix}/sqs-appointment-queue-url"
  type      = "String"
  value     = module.sqs.appointment_events_queue_url
  overwrite = true
}

resource "aws_ssm_parameter" "rds_endpoint" {
  name      = "${local.ssm_prefix}/rds-endpoint"
  type      = "String"
  value     = module.rds.db_endpoint
  overwrite = true
}

# ── NodePort access for load balancer → EKS nodes ────────────────────────────
# Envoy Gateway provisions an NLB; nodes must accept traffic on NodePort range.
resource "aws_security_group_rule" "node_nodeport_ingress" {
  type              = "ingress"
  from_port         = 30000
  to_port           = 32767
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
  security_group_id = module.eks.node_security_group_id
  description       = "NLB to NodePort range"
}

# ── DB credentials secret version (root-level to break security↔rds cycle) ───
resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = module.security.db_credentials_secret_arn
  secret_string = jsonencode({
    username = "dbadmin"
    password = module.rds.db_password
    host     = split(":", module.rds.db_endpoint)[0]
    port     = 5432
  })
}

# ── Route53 + ACM + CloudFront ────────────────────────────────────────────────

resource "aws_route53_zone" "main" {
  name = var.domain_name
  tags = { Project = var.project, Environment = var.environment, ManagedBy = "terraform" }
}

resource "aws_acm_certificate" "frontend" {
  domain_name       = "${var.app_subdomain}.${var.domain_name}"
  validation_method = "DNS"
  lifecycle { create_before_destroy = true }
  tags = { Name = "${var.app_subdomain}.${var.domain_name}" }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.frontend.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }
  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.main.zone_id
}

resource "aws_acm_certificate_validation" "frontend" {
  certificate_arn         = aws_acm_certificate.frontend.arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
  timeouts { create = "10m" }
}

# elb_hostname is passed by the workflow, which reads it from SSM.
# Bootstrap stores it after provisioning the ELB. Default "pending" skips CloudFront.
locals {
  cdn_ready = var.elb_hostname != "pending"
}

resource "aws_cloudfront_distribution" "frontend" {
  count      = local.cdn_ready ? 1 : 0
  depends_on = [aws_acm_certificate_validation.frontend]

  enabled         = true
  is_ipv6_enabled = true
  aliases         = ["${var.app_subdomain}.${var.domain_name}"]

  origin {
    domain_name = var.elb_hostname
    origin_id   = "elb"
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "elb"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    # CachingDisabled — dynamic app + API, never cache
    cache_policy_id = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    # AllViewerExceptHostHeader — forward all headers/cookies/query strings to origin
    origin_request_policy_id = "b689b0a8-53d0-40ab-baf2-68738e2966ac"
    min_ttl                  = 0
    default_ttl              = 0
    max_ttl                  = 0
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.frontend.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = { Name = "${var.project}-${var.environment}-cdn", Project = var.project }
}

resource "aws_route53_record" "frontend" {
  count   = local.cdn_ready ? 1 : 0
  zone_id = aws_route53_zone.main.zone_id
  name    = "${var.app_subdomain}.${var.domain_name}"
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.frontend[0].domain_name
    zone_id                = aws_cloudfront_distribution.frontend[0].hosted_zone_id
    evaluate_target_health = false
  }
}
