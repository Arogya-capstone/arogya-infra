variable "project" { type = string }
variable "environment" { type = string }
variable "owner" { type = string }
variable "region" { type = string }
variable "account_id" { type = string }
variable "kms_key_arn" { type = string }
variable "jwt_private_key" {
  type      = string
  sensitive = true
  default   = "REPLACE_WITH_ACTUAL_KEY"
}
variable "jwt_public_key" {
  type      = string
  sensitive = true
  default   = "REPLACE_WITH_ACTUAL_KEY"
}
variable "ses_sender_email" { type = string }
variable "namespace" { type = string }
variable "groq_api_key" {
  type      = string
  sensitive = true
  default   = "REPLACE_WITH_GROQ_KEY"
}
