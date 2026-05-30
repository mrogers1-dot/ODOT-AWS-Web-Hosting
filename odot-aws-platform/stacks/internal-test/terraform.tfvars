# terraform.tfvars — Variable values for the internal-test stack.

# ── Provider ───────────────────────────────────────────────────────────────────

assume_role_arn = "" # Empty = use current credentials (SSO profile).

# ── Networking ────────────────────────────────────────────────────────────────

vpc_cidr           = "10.4.0.0/16"
availability_zones = ["us-east-2a", "us-east-2b"]

# ── ECS Cluster ───────────────────────────────────────────────────────────────

cluster_name = "WebHosting-Test"

# ── Tags ──────────────────────────────────────────────────────────────────────

tags = {
  Environment = "test"
  Project     = "ODOTWebHosting"
  Owner       = "odot-platform-team"
}
