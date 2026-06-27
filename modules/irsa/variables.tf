variable "project" { type = string }
variable "environment" { type = string }
variable "owner" { type = string }
variable "namespace" { type = string }
variable "oidc_provider" { type = string }
variable "oidc_provider_arn" { type = string }
variable "kms_key_arn" { type = string }
variable "region" { type = string }
variable "account_id" { type = string }
variable "db_credentials_secret_arn" { type = string }
variable "jwt_private_key_secret_arn" { type = string }
variable "jwt_public_key_secret_arn" { type = string }
variable "ssm_parameter_prefix" { type = string }
variable "documents_bucket_arn" { type = string }
variable "rag_processing_queue_arn" { type = string }
variable "rag_processing_dlq_arn" { type = string }
variable "appointment_events_queue_arn" { type = string }
variable "groq_api_key_secret_arn" { type = string }
variable "github_org" { type = string }
variable "github_repo" { type = string }
variable "github_infra_repo" {
  type    = string
  default = "arogya-infra"
}
