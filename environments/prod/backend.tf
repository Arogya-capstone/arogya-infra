terraform {
  backend "s3" {
    bucket  = "arogya-tf-state-371454942267"
    key     = "prod/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
    use_lockfile = true
  }
}
