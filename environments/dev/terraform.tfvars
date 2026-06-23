project    = "arogya"
environment = "dev"
owner      = "arogya-team"
region     = "us-east-1"
account_id = "371454942267"

# VPC
vpc_cidr = "10.0.0.0/16"
azs      = ["us-east-1a", "us-east-1b"]

# EKS
cluster_name       = "arogya-dev-eks"
cluster_version    = "1.30"
node_instance_type = "t3.small"
node_min_size      = 1
node_max_size      = 3
node_desired_size  = 1

# RDS
rds_instance_class = "db.t3.micro"
rds_multi_az       = false

# Kubernetes namespace
namespace = "arogya-dev"

# GitHub (for OIDC federation)
github_org  = "Arogya-capstone"
github_repo = "arogya-app"

# Notifications
ops_email        = "neerajbalamurali@gmail.com"
ses_sender_email = "neerajbalamurali@gmail.com"
