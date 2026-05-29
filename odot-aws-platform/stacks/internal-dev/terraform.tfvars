# terraform.tfvars — Variable values for the internal-dev stack.
#
# Replace placeholder values (marked with PLACEHOLDER) with actual values
# before running `terraform apply`.

# ── Provider ───────────────────────────────────────────────────────────────────

assume_role_arn = "arn:aws:iam::577881328002:role/odot-terraform-deploy"

# ── Networking ────────────────────────────────────────────────────────────────

vpc_cidr           = "10.0.0.0/16"
availability_zones = ["us-east-2a", "us-east-2b"]

# ── ECS Cluster ───────────────────────────────────────────────────────────────

cluster_name = "WebHosting-Dev"

# ── Security ──────────────────────────────────────────────────────────────────

account_id            = "577881328002"                      # DOT-Web-Internal account ID
org_id                = "o-PLACEHOLDER"                     # PLACEHOLDER: AWS Organizations ID
config_s3_bucket_name = "odot-config-internal-577881328002" # S3 bucket for AWS Config delivery

# ── Monitoring ────────────────────────────────────────────────────────────────

slack_workspace_id = "T00000000"               # PLACEHOLDER: Slack workspace ID
slack_channel_id   = "C00000000"               # PLACEHOLDER: Slack channel ID for #aws-alerts-internal
alert_email        = "odot-alerts@example.com" # PLACEHOLDER: ServiceNow/FortiSIEM email
budget_limit_usd   = 1000

# ── OIDC ──────────────────────────────────────────────────────────────────────

github_org   = "odot-ohio"           # PLACEHOLDER: GitHub Enterprise org name
github_repos = ["odot-app-template"] # Repos allowed to deploy to this account

# ── Tags ──────────────────────────────────────────────────────────────────────

tags = {
  Environment = "dev"
  Project     = "ODOTWebHosting"
  Owner       = "odot-platform-team"
}
