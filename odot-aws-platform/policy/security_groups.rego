# policy/security_groups.rego
#
# OPA policy: No security group allows 0.0.0.0/0 ingress except external ALB SGs on port 443.
# Requirements: 21.3

package main

deny[msg] {
  resource := input.resource_changes[_]
  resource.type == "aws_vpc_security_group_ingress_rule"
  resource.change.actions[_] == "create"
  resource.change.after.cidr_ipv4 == "0.0.0.0/0"
  resource.change.after.from_port != 443
  msg := sprintf("Security group rule %s allows 0.0.0.0/0 on port %d (only 443 allowed for external ALBs)", [resource.address, resource.change.after.from_port])
}
