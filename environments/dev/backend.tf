terraform {
  backend "s3" {
    bucket         = "arogya-tf-state-371454942267"
    key            = "dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "arogya-tf-locks"
    encrypt        = true
  }
}
