variable "github_org" {
  description = "GitHub organization name (e.g., 'odot-ohio')"
  type        = string
}

variable "github_repos" {
  description = "List of GitHub repository names that are allowed to assume the IAM role (e.g., ['my-app', 'another-app'])"
  type        = list(string)
}

variable "account_id" {
  description = "AWS account ID where the OIDC provider and IAM role are created"
  type        = string
}

variable "account_type" {
  description = "Account type — 'internal' or 'external'. Used in the IAM role name."
  type        = string

  validation {
    condition     = contains(["internal", "external"], var.account_type)
    error_message = "account_type must be 'internal' or 'external'."
  }
}

variable "tags" {
  description = "Tags to apply to all resources. Must include Environment, Project, and Owner."
  type        = map(string)
  default     = {}
}
