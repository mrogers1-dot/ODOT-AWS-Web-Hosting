# modules/admin-dashboard/cognito.tf
#
# Provisions Cognito User Pool for the admin dashboard.
#
# When enable_okta_federation = true (production):
#   Okta is configured as a federated OIDC identity provider.
#   Authentication flow: Okta OIDC → Cognito User Pool → Dashboard app.
#   Okta groups are mapped to custom:role for RBAC.
#
# When enable_okta_federation = false (POC):
#   No federated IdP. Users are created directly in the Cognito User Pool.
#   Authentication flow: Cognito Hosted UI (email/password) → Dashboard app.
#   custom:role is set manually on each user via admin-create-user.
#
# Requirements: 14.1, 14.2

locals {
  default_tags = {
    Project = "ODOTWebHosting"
    Owner   = "odot-platform-team"
  }
  merged_tags = merge(local.default_tags, var.tags)
}

# ── Cognito User Pool ─────────────────────────────────────────────────────────
resource "aws_cognito_user_pool" "dashboard" {
  name = "odot-dashboard-${var.stage}"

  # Disable self-signup — users are either federated via Okta or admin-created
  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  # Password policy (required for local users in POC; harmless when federated)
  password_policy {
    minimum_length    = 8
    require_uppercase = true
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
  }

  # Custom attribute for role mapping
  schema {
    name                = "role"
    attribute_data_type = "String"
    mutable             = true

    string_attribute_constraints {
      min_length = 1
      max_length = 50
    }
  }

  tags = merge(local.merged_tags, {
    Name = "odot-dashboard-${var.stage}"
  })
}

# ── Cognito User Pool Domain ──────────────────────────────────────────────────
resource "aws_cognito_user_pool_domain" "dashboard" {
  domain       = var.cognito_domain_prefix
  user_pool_id = aws_cognito_user_pool.dashboard.id
}

# ── Okta Identity Provider (production only) ──────────────────────────────────
#
# Only created when enable_okta_federation = true.
# Configures Okta as an OIDC identity provider in Cognito.
resource "aws_cognito_identity_provider" "okta" {
  count = var.enable_okta_federation ? 1 : 0

  user_pool_id  = aws_cognito_user_pool.dashboard.id
  provider_name = "Okta"
  provider_type = "OIDC"

  provider_details = {
    authorize_scopes          = "openid profile email groups"
    client_id                 = var.okta_client_id
    client_secret             = var.okta_client_secret
    oidc_issuer               = var.okta_issuer_url
    attributes_request_method = "GET"
  }

  # Attribute mapping: Okta claims → Cognito user attributes
  attribute_mapping = {
    email         = "email"
    username      = "sub"
    "custom:role" = "groups"
  }
}

# ── Cognito App Client ────────────────────────────────────────────────────────
#
# When federated (production): uses Okta as the only IdP, generates a client secret.
# When local (POC): uses COGNITO as the IdP, no client secret (public client).
resource "aws_cognito_user_pool_client" "dashboard" {
  name         = "odot-dashboard-client-${var.stage}"
  user_pool_id = aws_cognito_user_pool.dashboard.id

  # Authorization code flow (most secure for web apps)
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["openid", "profile", "email"]

  # Identity providers — Okta when federated, COGNITO when local
  supported_identity_providers = var.enable_okta_federation ? ["Okta"] : ["COGNITO"]

  # Callback and logout URLs
  callback_urls = var.callback_urls
  logout_urls   = var.logout_urls

  # Token validity
  access_token_validity  = 1  # 1 hour
  id_token_validity      = 1  # 1 hour
  refresh_token_validity = 24 # 24 hours

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "hours"
  }

  # Client secret: required for confidential client (Okta flow), not needed for public client (POC)
  generate_secret = var.enable_okta_federation

  depends_on = [aws_cognito_identity_provider.okta]
}
