project     = "arogya"
environment = "prod"
owner       = "arogya-team"
region      = "us-east-1"
account_id  = "371454942267"

# VPC
vpc_cidr = "10.1.0.0/16"
azs      = ["us-east-1a", "us-east-1b"]

# EKS
cluster_name       = "arogya-prod-eks"
cluster_version    = "1.30"
node_instance_type = "t3.medium"
node_min_size      = 2
node_max_size      = 6
node_desired_size  = 3

# RDS
rds_instance_class = "db.t3.micro"
rds_multi_az       = false

# Kubernetes namespace
namespace = "arogya-prod"

# Domain
domain_name   = "neeraj.bond"
app_subdomain = "arogya"

# Notifications
ops_email        = "medilinkhub.team@gmail.com"
ses_sender_email = "medilinkhub.team@gmail.com"
# EKS admin access
admin_iam_arns = [
  "arn:aws:iam::371454942267:user/Neeraj"
]

elb_hostname = "a5f20c7854c204acb8c55e4e41ed1ee9-252504159.us-east-1.elb.amazonaws.com"

# last-updated: 2026-06-30T00:00:00Z
