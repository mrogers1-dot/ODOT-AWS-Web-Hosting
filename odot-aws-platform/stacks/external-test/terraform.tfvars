# terraform.tfvars — Variable values for the external-test stack.
#
# Replace placeholder values (marked with PLACEHOLDER) with actual values
# before running `terraform apply`.

# ── Provider ───────────────────────────────────────────────────────────────────

assume_role_arn = "arn:aws:iam::549136075921:role/odot-terraform-deploy"

# ── Networking ────────────────────────────────────────────────────────────────

vpc_cidr           = "10.1.16.0/16"
availability_zones = ["us-east-2a", "us-east-2b"]

# ── ECS Cluster ───────────────────────────────────────────────────────────────

cluster_name = "WebHosting-Test"

# ── Security ──────────────────────────────────────────────────────────────────

account_id            = "549136075921"                      # DOT-Web-External account ID
org_id                = "o-PLACEHOLDER"                     # PLACEHOLDER: AWS Organizations ID
config_s3_bucket_name = "odot-config-external-549136075921" # S3 bucket for AWS Config delivery

# ── Monitoring ────────────────────────────────────────────────────────────────

slack_workspace_id = "T00000000"               # PLACEHOLDER: Slack workspace ID
slack_channel_id   = "C00000000"               # PLACEHOLDER: Slack channel ID for #aws-alerts-external
alert_email        = "odot-alerts@example.com" # PLACEHOLDER: ServiceNow/FortiSIEM email
budget_limit_usd   = 1000

# ── OIDC ──────────────────────────────────────────────────────────────────────

github_org   = "odot-ohio"           # PLACEHOLDER: GitHub Enterprise org name
github_repos = ["odot-app-template"] # Repos allowed to deploy to this account

# ── WAF ───────────────────────────────────────────────────────────────────────

waf_acl_arn = "arn:aws:wafv2:us-east-2:549136075921:regional/webacl/odot-external-waf/PLACEHOLDER" # PLACEHOLDER: WAF Web ACL ARN

# ── Tags ──────────────────────────────────────────────────────────────────────

tags = {
  Environment = "test"
  Project     = "ODOTWebHosting"
  Owner       = "odot-platform-team"
}
