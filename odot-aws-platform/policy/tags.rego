# policy/tags.rego
#
# OPA policy: All planned resources must have Environment, Project, and Owner tags.
# Requirements: 21.3

package main

deny[msg] {
  resource := input.resource_changes[_]
  resource.change.actions[_] == "create"
  tags := object.get(resource.change.after, "tags", {})
  not tags.Environment
  msg := sprintf("Resource %s is missing required 'Environment' tag", [resource.address])
}

deny[msg] {
  resource := input.resource_changes[_]
  resource.change.actions[_] == "create"
  tags := object.get(resource.change.after, "tags", {})
  not tags.Project
  msg := sprintf("Resource %s is missing required 'Project' tag", [resource.address])
}

deny[msg] {
  resource := input.resource_changes[_]
  resource.change.actions[_] == "create"
  tags := object.get(resource.change.after, "tags", {})
  not tags.Owner
  msg := sprintf("Resource %s is missing required 'Owner' tag", [resource.address])
}
