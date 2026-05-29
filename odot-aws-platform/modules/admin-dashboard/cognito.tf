# modules/admin-dashboard/cognito.tf
#
# Provisions Cognito User Pool with Okta as a federated identity provider.
# Authentication flow: Okta OIDC → Cognito User Pool → Dashboard app.
#
# Okta groups are mapped to the custom:role attribute in Cognito, which the
# dashboard backend uses for RBAC (Admin vs Developer role enforcement).
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
#
# The User Pool acts as the identity broker between Okta (corporate IdP) and
# the dashboard application. Users never create Cognito-native accounts —
# all authentication flows through Okta federation.
resource "aws_cognito_user_pool" "dashboard" {
  name = "odot-dashboard-${var.stage}"

  # Disable self-signup — all users must authenticate via Okta federation
  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  # Custom attribute for role mapping from Okta groups
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
#
# Hosted UI domain for the Cognito login page. Users are redirected here
# and then forwarded to Okta for authentication.
resource "aws_cognito_user_pool_domain" "dashboard" {
  domain       = var.cognito_domain_prefix
  user_pool_id = aws_cognito_user_pool.dashboard.id
}

# ── Okta Identity Provider ────────────────────────────────────────────────────
#
# Configures Okta as an OIDC identity provider in Cognito. The attribute
# mapping translates Okta's "groups" claim into Cognito's custom:role attribute,
# enabling role-based access control in the dashboard.
resource "aws_cognito_identity_provider" "okta" {
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
  # The "groups" claim from Okta is mapped to custom:role for RBAC
  attribute_mapping = {
    email          = "email"
    username       = "sub"
    "custom:role"  = "groups"
  }
}

# ── Cognito App Client ────────────────────────────────────────────────────────
#
# The app client used by the dashboard frontend. Configured for authorization
# code flow (not implicit) for security. Supports Okta as the only IdP.
resource "aws_cognito_user_pool_client" "dashboard" {
  name         = "odot-dashboard-client-${var.stage}"
  user_pool_id = aws_cognito_user_pool.dashboard.id

  # Authorization code flow (most secure for web apps)
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["openid", "profile", "email"]

  # Supported identity providers — Okta only (no Cognito-native login)
  supported_identity_providers = [aws_cognito_identity_provider.okta.provider_name]

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

  # Generate a client secret for server-side token exchange
  generate_secret = true
}
