variable "project" { type = string }
variable "environment" { type = string }
variable "owner" { type = string }
variable "region" { type = string }
variable "account_id" { type = string }
variable "vpc_cidr" { type = string }
variable "azs" { type = list(string) }
variable "cluster_name" { type = string }
variable "cluster_version" { type = string }
variable "node_instance_type" { type = string }
variable "node_min_size" { type = number }
variable "node_max_size" { type = number }
variable "node_desired_size" { type = number }
variable "rds_instance_class" { type = string }
variable "rds_multi_az" { type = bool }
variable "namespace" { type = string }
variable "ops_email" { type = string }
variable "ses_sender_email" { type = string }
variable "domain_name" { type = string }
variable "app_subdomain" { type = string }
variable "elb_hostname" {
  type    = string
  default = "pending"
}
variable "groq_api_key" {
  type      = string
  sensitive = true
  default   = "REPLACE_WITH_GROQ_KEY"
}
