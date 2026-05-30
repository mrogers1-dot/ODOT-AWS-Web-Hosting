# terraform.tfvars — Variable values for the external-test stack.

# ── Provider ───────────────────────────────────────────────────────────────────

assume_role_arn = "" # Empty = use current credentials (SSO profile). Set for CI/CD cross-account.

# ── Networking ────────────────────────────────────────────────────────────────

vpc_cidr           = "10.2.0.0/16"
availability_zones = ["us-east-2a", "us-east-2b"]

# ── ECS Cluster ───────────────────────────────────────────────────────────────

cluster_name = "WebHosting-Test"

# ── Security ──────────────────────────────────────────────────────────────────

account_id            = "549136075921"                      # DOT-Web-External account ID
org_id                = "o-ixc0lqn4jr"                      # AWS Organizations ID
config_s3_bucket_name = "odot-config-external-549136075921" # S3 bucket for AWS Config delivery

# These services are already enabled by AWS Organizations — skip creation
enable_guardduty   = false
enable_securityhub = false
enable_config      = false
enable_macie       = false

# ── Monitoring ────────────────────────────────────────────────────────────────

slack_workspace_id = "T0B72DR9L5U"               # Demo Slack workspace
slack_channel_id   = "C0B74G0EN0J"               # Demo Slack channel for external alerts
alert_email        = "odot-alerts@example.com"   # PLACEHOLDER: ServiceNow/FortiSIEM email
budget_limit_usd   = 1000

# ── OIDC ──────────────────────────────────────────────────────────────────────

github_org   = "ftvizsla"                                  # Personal GitHub (temp for testing)
github_repos = ["odot-app-template", "odot-aws-platform"]  # Repos allowed to deploy to this account

# ── WAF ───────────────────────────────────────────────────────────────────────

waf_acl_arn = "" # WAF will be created later — leave empty for initial deploy

# ── Tags ──────────────────────────────────────────────────────────────────────

tags = {
  Environment = "test"
  Project     = "ODOTWebHosting"
  Owner       = "odot-platform-team"
}
