# modules/networking/vpc-endpoints.tf
#
# VPC interface endpoints and S3 gateway endpoint for Internal_Account VPCs.
# These enable Fargate tasks to reach AWS services (ECR, CloudWatch Logs,
# Secrets Manager, SSM, STS) without any internet egress path.
#
# Internal VPCs have no IGW and no NAT by design (zero-egress). Without these
# endpoints, ECS tasks would fail with CannotPullContainerError because they
# cannot reach ECR or CloudWatch Logs APIs.
#
# External VPCs do NOT need these endpoints — they have NAT gateways for egress.
#
# Requirements: 15.1, 15.2, 15.3, 15.4, 15.5, 15.6, 15.7

locals {
  # The 7 interface endpoints required for Fargate tasks in a zero-egress VPC.
  # Each endpoint creates ENIs in the private subnets, allowing private DNS
  # resolution of the service's public hostname to the endpoint's private IP.
  interface_endpoint_services = [
    "ecr.api",        # ECR API calls (GetAuthorizationToken, DescribeRepositories)
    "ecr.dkr",        # Docker registry protocol (image pull)
    "logs",           # CloudWatch Logs (awslogs driver delivery)
    "secretsmanager", # Secrets Manager (task definition secret references)
    "ssm",            # SSM Parameter Store (configuration retrieval)
    "ssmmessages",    # SSM Session Manager / ECS Exec channel
    "sts",            # STS (AssumeRole for cross-account dashboard access)
  ]
}

# ── VPC Endpoint Security Group ───────────────────────────────────────────────
#
# A dedicated security group for all interface endpoints. Allows inbound HTTPS
# (port 443) only from the VPC CIDR — no other traffic is permitted.
# This ensures only resources within the VPC can reach the endpoints.
resource "aws_security_group" "vpc_endpoints" {
  count = local.is_internal ? 1 : 0

  name        = "odot-${var.account_type}-${var.stage}-vpce-sg"
  description = "Security group for VPC interface endpoints — allows HTTPS from VPC CIDR only"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.merged_tags, {
    Name = "odot-${var.account_type}-${var.stage}-vpce-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "vpce_https" {
  count = local.is_internal ? 1 : 0

  security_group_id = aws_security_group.vpc_endpoints[0].id
  description       = "Allow HTTPS from VPC CIDR to interface endpoints"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = var.vpc_cidr

  tags = merge(local.merged_tags, {
    Name = "odot-${var.account_type}-${var.stage}-vpce-https-ingress"
  })
}

# ── Interface Endpoints ───────────────────────────────────────────────────────
#
# One interface endpoint per required AWS service. Each endpoint creates ENIs
# in the private subnets (one per AZ for high availability). Private DNS is
# enabled so that the standard AWS service hostnames (e.g., ecr.us-east-2.amazonaws.com)
# resolve to the endpoint's private IPs within the VPC.
resource "aws_vpc_endpoint" "interface" {
  for_each = local.is_internal ? toset(local.interface_endpoint_services) : toset([])

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true

  tags = merge(local.merged_tags, {
    Name = "odot-${var.account_type}-${var.stage}-vpce-${each.value}"
  })
}

# ── S3 Gateway Endpoint ───────────────────────────────────────────────────────
#
# ECR stores container image layers in S3. A Gateway endpoint (not interface)
# is required for the ECS agent to download these layers. Gateway endpoints
# are free, route via route-table entries, and don't require ENIs or security
# groups. The endpoint is associated with all private route tables.
resource "aws_vpc_endpoint" "s3" {
  count = local.is_internal ? 1 : 0

  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.private[*].id

  tags = merge(local.merged_tags, {
    Name = "odot-${var.account_type}-${var.stage}-vpce-s3"
  })
}
