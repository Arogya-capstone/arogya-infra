variable "project" { type = string }
variable "environment" { type = string }
variable "owner" { type = string }
variable "cluster_name" { type = string }
variable "cluster_version" {
  type    = string
  default = "1.30"
}
variable "vpc_id" { type = string }
variable "subnet_ids" { type = list(string) }
variable "node_instance_type" {
  type    = string
  default = "t3.medium"
}
variable "node_min_size" {
  type    = number
  default = 1
}
variable "node_max_size" {
  type    = number
  default = 6
}
variable "node_desired_size" {
  type    = number
  default = 2
}
variable "kms_key_arn" { type = string }
