# Bootstrap import: github-actions role created manually before Terraform ran.
# Remove this file after the first successful apply.
import {
  to = module.irsa.aws_iam_role.github_actions
  id = "arogya-prod-github-actions"
}
