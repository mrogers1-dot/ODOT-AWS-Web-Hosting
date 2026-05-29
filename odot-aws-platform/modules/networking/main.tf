# modules/networking/main.tf
#
# Provisions a VPC and all subnet/routing resources for one account-stage
# combination. Behaviour diverges based on account_type:
#
#   internal — private subnets only; no IGW, no public subnets, no NAT gateway,
#              no 0.0.0.0/0 route anywhere. Traffic enters only via Client VPN
#              or Direct Connect. (Requirements 2.1, 2.3, 2.4)
#
#   external — public subnets (IGW-attached) + private subnets (NAT gateway
#              for egress). ALBs live in public subnets; ECS tasks live in
#              private subnets. (Requirements 3.1, 3.2)
#
# Requirements: 2.1, 2.3, 2.4, 3.1, 3.2

locals {
  # Merge caller-supplied tags with module-level defaults so every resource
  # always carries the three mandatory tags (Environment, Project, Owner).
  default_tags = {
    Project = "ODOTWebHosting"
    Owner   = "odot-platform-team"
  }
  merged_tags = merge(local.default_tags, var.tags)

  # Convenience flags — used throughout to gate resource creation.
  is_external = var.account_type == "external"
  is_internal = var.account_type == "internal"

  # Number of AZs drives the subnet count for both public and private tiers.
  az_count = length(var.availability_zones)
}

# ── VPC ───────────────────────────────────────────────────────────────────────
#
# Named odot-{account_type}-{stage} per the design naming convention.
# DNS hostnames and DNS resolution are enabled so that ECS tasks can resolve
# ECR and other AWS service endpoints via Route 53 Resolver.
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.merged_tags, {
    Name = "odot-${var.account_type}-${var.stage}"
  })
}

# ── Private Subnets ───────────────────────────────────────────────────────────
#
# One private subnet per AZ. Created for both internal and external accounts.
#
# cidrsubnet() carves the VPC CIDR into equal /24 blocks. For external accounts
# the private subnets start at index az_count (after the public subnets) so
# that CIDR ranges never overlap.
#
# map_public_ip_on_launch is explicitly false (the default) — stated here for
# clarity and to satisfy the internal-account property test (Property 12).
resource "aws_subnet" "private" {
  count = local.az_count

  vpc_id = aws_vpc.main.id

  # External: private subnets occupy the second half of the /24 blocks
  # (indices az_count .. 2*az_count-1) so they don't overlap with public subnets.
  # Internal: private subnets start at index 0 — there are no public subnets.
  cidr_block = local.is_external ? cidrsubnet(var.vpc_cidr, 8, count.index + local.az_count) : cidrsubnet(var.vpc_cidr, 8, count.index)

  availability_zone = var.availability_zones[count.index]

  # Never assign public IPs to instances in private subnets.
  map_public_ip_on_launch = false

  tags = merge(local.merged_tags, {
    Name = "odot-${var.account_type}-${var.stage}-private-${var.availability_zones[count.index]}"
    Tier = "private"
  })
}

# ── Public Subnets (external account only) ────────────────────────────────────
#
# One public subnet per AZ. Only created when account_type = "external".
# ALBs are placed here; ECS tasks are placed in private subnets.
#
# map_public_ip_on_launch = true so that resources launched directly into these
# subnets (e.g., NAT gateway ENIs) receive a public IP automatically.
resource "aws_subnet" "public" {
  count = local.is_external ? local.az_count : 0

  vpc_id = aws_vpc.main.id

  # Public subnets occupy the first az_count /24 blocks (indices 0 .. az_count-1).
  cidr_block = cidrsubnet(var.vpc_cidr, 8, count.index)

  availability_zone = var.availability_zones[count.index]

  # Instances launched into public subnets receive a public IP by default.
  # This is required for the NAT gateway to obtain its public address.
  map_public_ip_on_launch = true

  tags = merge(local.merged_tags, {
    Name = "odot-${var.account_type}-${var.stage}-public-${var.availability_zones[count.index]}"
    Tier = "public"
  })
}

# ── Internet Gateway (external account only) ──────────────────────────────────
#
# Provides the VPC with a path to/from the public internet.
# NOT created for internal accounts — the SCP on the internal account also
# denies ec2:CreateInternetGateway as a defence-in-depth measure.
resource "aws_internet_gateway" "main" {
  count = local.is_external ? 1 : 0

  vpc_id = aws_vpc.main.id

  tags = merge(local.merged_tags, {
    Name = "odot-${var.account_type}-${var.stage}-igw"
  })
}

# ── Elastic IPs for NAT Gateways (external account only) ─────────────────────
#
# One EIP per AZ so that each NAT gateway has a stable, predictable public IP.
# Placing a NAT gateway in each AZ avoids cross-AZ data transfer charges and
# eliminates the NAT gateway as a single point of failure.
resource "aws_eip" "nat" {
  count = local.is_external ? local.az_count : 0

  # domain = "vpc" is required for EIPs used with NAT gateways (replaces the
  # deprecated vpc = true argument in provider ~> 5.0).
  domain = "vpc"

  # Ensure the IGW exists before allocating EIPs — AWS requires the VPC to
  # have an IGW before EIPs can be associated with NAT gateways in that VPC.
  depends_on = [aws_internet_gateway.main]

  tags = merge(local.merged_tags, {
    Name = "odot-${var.account_type}-${var.stage}-nat-eip-${var.availability_zones[count.index]}"
  })
}

# ── NAT Gateways (external account only) ─────────────────────────────────────
#
# One NAT gateway per AZ, placed in the corresponding public subnet.
# Private subnets route 0.0.0.0/0 to the NAT gateway in the same AZ to keep
# egress traffic local and avoid cross-AZ charges.
resource "aws_nat_gateway" "main" {
  count = local.is_external ? local.az_count : 0

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(local.merged_tags, {
    Name = "odot-${var.account_type}-${var.stage}-nat-${var.availability_zones[count.index]}"
  })

  depends_on = [aws_internet_gateway.main]
}

# ── Public Route Table (external account only) ────────────────────────────────
#
# A single route table shared by all public subnets. The default route
# (0.0.0.0/0) points to the internet gateway, enabling inbound and outbound
# internet traffic for resources in public subnets (ALBs, NAT gateways).
resource "aws_route_table" "public" {
  count = local.is_external ? 1 : 0

  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main[0].id
  }

  tags = merge(local.merged_tags, {
    Name = "odot-${var.account_type}-${var.stage}-rt-public"
  })
}

# Associate every public subnet with the public route table.
resource "aws_route_table_association" "public" {
  count = local.is_external ? local.az_count : 0

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public[0].id
}

# ── Private Route Tables ──────────────────────────────────────────────────────
#
# One route table per private subnet (one per AZ).
#
# External account: each private route table has a 0.0.0.0/0 route pointing to
# the NAT gateway in the same AZ, enabling outbound-only internet access for
# ECS tasks (e.g., pulling images from ECR public, calling external APIs).
#
# Internal account: route tables have NO 0.0.0.0/0 route. The only routes are
# the implicit local route (VPC CIDR) and any VPN/Direct Connect propagated
# routes. This satisfies Requirement 2.3 and Property 12.
resource "aws_route_table" "private" {
  count = local.az_count

  vpc_id = aws_vpc.main.id

  # External: add a default route to the NAT gateway in the same AZ.
  # Internal: no dynamic route block — only the implicit local route exists.
  dynamic "route" {
    for_each = local.is_external ? [count.index] : []
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = aws_nat_gateway.main[route.value].id
    }
  }

  tags = merge(local.merged_tags, {
    Name = "odot-${var.account_type}-${var.stage}-rt-private-${var.availability_zones[count.index]}"
  })
}

# Associate each private subnet with its corresponding per-AZ route table.
resource "aws_route_table_association" "private" {
  count = local.az_count

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}
