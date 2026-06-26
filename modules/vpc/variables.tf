variable "project" { type = string }
variable "environment" { type = string }
variable "owner" { type = string }
variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}
variable "azs" { type = list(string) }
variable "cluster_name" { type = string }
