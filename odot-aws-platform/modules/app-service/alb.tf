# modules/app-service/alb.tf
#
# Application Load Balancer, target group, listener, security groups,
# and WAF association for the app-service module.
#
# - Internal account: ALB scheme is "internal" (private, no public access)
# - External account: ALB scheme is "internet-facing" with WAF association
#   and the `waf-managed = true` tag required by the SCP enforcement pattern
#
# Requirements: 3.3, 3.4, 3.5

# -----------------------------------------------------------------------------
# Security Groups
# -----------------------------------------------------------------------------

# ALB Security Group — allows inbound HTTP (80) and HTTPS (443) traffic
resource "aws_security_group" "alb" {
  name        = "odot-${var.app_name}-${var.stage}-alb-sg"
  description = "Security group for ${var.app_name} ALB - allows inbound HTTP/HTTPS"
  vpc_id      = var.vpc_id

  tags = merge(local.default_tags, var.tags, {
    Name = "odot-${var.app_name}-${var.stage}-alb-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "Allow inbound HTTP traffic"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"

  tags = merge(local.default_tags, var.tags)
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  description       = "Allow inbound HTTPS traffic"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"

  tags = merge(local.default_tags, var.tags)
}

resource "aws_vpc_security_group_egress_rule" "alb_to_ecs" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Allow outbound traffic to ECS tasks on container port"
  from_port                    = var.container_port
  to_port                      = var.container_port
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.ecs.id

  tags = merge(local.default_tags, var.tags)
}

# ECS Security Group — allows inbound traffic from ALB on the container port
resource "aws_security_group" "ecs" {
  name        = "odot-${var.app_name}-${var.stage}-ecs-sg"
  description = "Security group for ${var.app_name} ECS tasks - allows inbound from ALB"
  vpc_id      = var.vpc_id

  tags = merge(local.default_tags, var.tags, {
    Name = "odot-${var.app_name}-${var.stage}-ecs-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "ecs_from_alb" {
  security_group_id            = aws_security_group.ecs.id
  description                  = "Allow inbound traffic from ALB on container port"
  from_port                    = var.container_port
  to_port                      = var.container_port
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.alb.id

  tags = merge(local.default_tags, var.tags)
}

resource "aws_vpc_security_group_egress_rule" "ecs_egress" {
  security_group_id = aws_security_group.ecs.id
  description       = "Allow all outbound traffic from ECS tasks"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

  tags = merge(local.default_tags, var.tags)
}

# -----------------------------------------------------------------------------
# Application Load Balancer
# -----------------------------------------------------------------------------

resource "aws_lb" "this" {
  name               = "odot-${var.app_name}-${var.stage}-alb"
  internal           = var.account_type == "internal"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.alb_subnet_ids

  # Enable deletion protection in production
  enable_deletion_protection = var.stage == "prod"

  # ALB access logging — delivers detailed request logs to S3 for traffic
  # analysis, security investigation, and dashboard user-stats panel.
  # Requirements: 17.1
  access_logs {
    bucket  = aws_s3_bucket.alb_logs.id
    prefix  = var.app_name
    enabled = true
  }

  # For external accounts, the waf-managed tag is required by the SCP
  # enforcement pattern to allow ALB creation without being denied.
  tags = merge(
    local.default_tags,
    var.tags,
    { Name = "odot-${var.app_name}-${var.stage}-alb" },
    var.account_type == "external" ? { "waf-managed" = "true" } : {}
  )
}

# -----------------------------------------------------------------------------
# Target Group
# -----------------------------------------------------------------------------

resource "aws_lb_target_group" "this" {
  name        = "odot-${var.app_name}-${var.stage}-tg"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip" # Required for awsvpc network mode (Fargate)

  health_check {
    enabled             = true
    path                = "/"
    port                = tostring(var.container_port)
    protocol            = "HTTP"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200-399"
  }

  tags = merge(local.default_tags, var.tags, {
    Name = "odot-${var.app_name}-${var.stage}-tg"
  })
}

# -----------------------------------------------------------------------------
# ALB Listener — HTTPS (443)
# TLS termination with ACM certificate and modern security policy.
# Requirements: 16.2
# -----------------------------------------------------------------------------

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }

  tags = merge(local.default_tags, var.tags)
}

# -----------------------------------------------------------------------------
# ALB Listener — HTTP (80) → HTTPS Redirect
# All HTTP traffic is permanently redirected to HTTPS. No plaintext serving.
# Requirements: 16.3
# -----------------------------------------------------------------------------

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  tags = merge(local.default_tags, var.tags)
}

# -----------------------------------------------------------------------------
# WAF Association (External Account Only)
# -----------------------------------------------------------------------------

# Associate the WAF Web ACL with the ALB when running in the external account.
# This ensures the ALB is protected before serving any traffic.
# The count condition requires both external account type AND a non-empty WAF ARN.
resource "aws_wafv2_web_acl_association" "this" {
  count = var.account_type == "external" && var.waf_acl_arn != "" ? 1 : 0

  resource_arn = aws_lb.this.arn
  web_acl_arn  = var.waf_acl_arn
}

# -----------------------------------------------------------------------------
# ALB Access Logs S3 Bucket
# Stores detailed request logs for traffic analysis and security investigation.
# Requirements: 17.1, 17.2, 17.3, 17.4
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "alb_logs" {
  bucket = "odot-alb-logs-${var.app_name}-${var.account_type}-${var.stage}"

  tags = merge(local.default_tags, var.tags, {
    Name = "odot-alb-logs-${var.app_name}-${var.account_type}-${var.stage}"
  })
}

resource "aws_s3_bucket_server_side_encryption_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    id     = "transition-and-expire"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    expiration {
      days = 365
    }
  }
}

# Bucket policy granting the ELB service account and log delivery service
# permission to write ALB access logs.
data "aws_elb_service_account" "main" {}

resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowELBLogDelivery"
        Effect    = "Allow"
        Principal = { AWS = data.aws_elb_service_account.main.arn }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.alb_logs.arn}/*"
      },
      {
        Sid       = "AllowLogDeliveryService"
        Effect    = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.alb_logs.arn}/*"
        Condition = {
          StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" }
        }
      },
      {
        Sid       = "AllowLogDeliveryServiceAclCheck"
        Effect    = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.alb_logs.arn
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Route 53 DNS Record
# Points the application domain to the ALB via an alias record.
# Requirements: 16.4
# -----------------------------------------------------------------------------

resource "aws_route53_record" "app" {
  count = var.domain_name != "" && var.hosted_zone_id != "" ? 1 : 0

  zone_id = var.hosted_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = true
  }
}
