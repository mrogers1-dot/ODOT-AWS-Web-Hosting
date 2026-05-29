# modules/networking/outputs.tf
#
# Outputs consumed by stack configurations and other modules (ecs-cluster,
# app-service) that need to place resources inside this VPC.
#
# Requirements: 2.1, 2.3, 2.4, 3.1, 3.2

output "vpc_id" {
  description = "ID of the VPC created by this module."
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "The IPv4 CIDR block of the VPC. Useful for security group ingress rules scoped to the VPC."
  value       = aws_vpc.main.cidr_block
}

output "private_subnet_ids" {
  description = "List of private subnet IDs, one per Availability Zone. ECS tasks and other private workloads are placed here."
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "List of public subnet IDs, one per Availability Zone. ALBs are placed here for external accounts. Returns an empty list for internal accounts (no public subnets are created)."
  value       = aws_subnet.public[*].id
}

output "vpc_endpoint_ids" {
  description = "Map of VPC endpoint service name to endpoint ID. Only populated for internal accounts (zero-egress VPCs with interface endpoints)."
  value       = { for k, v in aws_vpc_endpoint.interface : k => v.id }
}

output "s3_endpoint_id" {
  description = "ID of the S3 gateway endpoint. Only populated for internal accounts."
  value       = length(aws_vpc_endpoint.s3) > 0 ? aws_vpc_endpoint.s3[0].id : ""
}
