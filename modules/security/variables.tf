variable "project" { type = string }
variable "environment" { type = string }
variable "owner" { type = string }
variable "region" { type = string }
variable "account_id" { type = string }
variable "db_password" { type = string; sensitive = true }
variable "jwt_private_key" { type = string; sensitive = true; default = "REPLACE_WITH_ACTUAL_KEY" }
variable "jwt_public_key" { type = string; sensitive = true; default = "REPLACE_WITH_ACTUAL_KEY" }
variable "ses_sender_email" { type = string }
variable "namespace" { type = string }
variable "documents_bucket_name" { type = string; default = "" }
variable "rag_processing_queue_url" { type = string; default = "" }
variable "appointment_events_queue_url" { type = string; default = "" }
variable "rds_endpoint" { type = string; default = "" }
variable "groq_api_key" { type = string; sensitive = true; default = "REPLACE_WITH_GROQ_KEY" }
