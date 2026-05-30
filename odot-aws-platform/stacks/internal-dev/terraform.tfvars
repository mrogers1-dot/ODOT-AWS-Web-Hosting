# terraform.tfvars — Variable values for the internal-dev stack.
#
# Replace placeholder values (marked with PLACEHOLDER) with actual values
# before running `terraform apply`.

# ── Provider ───────────────────────────────────────────────────────────────────

assume_role_arn = "" # Empty = use current credentials (SSO profile). Set for CI/CD cross-account.

# ── Networking ────────────────────────────────────────────────────────────────

vpc_cidr           = "10.0.0.0/16"
availability_zones = ["us-east-2a", "us-east-2b"]

# ── ECS Cluster ───────────────────────────────────────────────────────────────

cluster_name = "WebHosting-Dev"

# ── Security ──────────────────────────────────────────────────────────────────

account_id            = "577881328002"                      # DOT-Web-Internal account ID
org_id                = "o-ixc0lqn4jr"                      # AWS Organizations ID
config_s3_bucket_name = "odot-config-internal-577881328002" # S3 bucket for AWS Config delivery

# These services are already enabled by AWS Organizations — skip creation
enable_guardduty   = false
enable_securityhub = false
enable_config      = false
enable_macie       = false

# ── Monitoring ────────────────────────────────────────────────────────────────

slack_workspace_id = "T0B72DR9L5U"               # Demo Slack workspace (replace with enterprise ID when ready)
slack_channel_id   = "C0B74FW9W7L"               # Demo Slack channel (replace with enterprise #aws-alerts-internal when ready)
alert_email        = "odot-alerts@example.com" # PLACEHOLDER: ServiceNow/FortiSIEM email
budget_limit_usd   = 1000

# ── OIDC ──────────────────────────────────────────────────────────────────────

github_org   = "ftvizsla"                                  # Personal GitHub (temp for testing)
github_repos = ["odot-app-template", "odot-aws-platform"]  # Repos allowed to deploy to this account

# ── Tags ──────────────────────────────────────────────────────────────────────

tags = {
  Environment = "dev"
  Project     = "ODOTWebHosting"
  Owner       = "odot-platform-team"
}
