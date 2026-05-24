output "vpc_id" {
  description = "ID of the VPC."
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC."
  value       = module.vpc.vpc_cidr_block
}

output "private_subnet_ids" {
  description = "IDs of private subnets."
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "IDs of public subnets."
  value       = module.vpc.public_subnets
}

output "nat_gateway_ids" {
  description = "IDs of NAT gateways."
  value       = module.vpc.natgw_ids
}

output "private_route_table_ids" {
  description = "IDs of private route tables."
  value       = module.vpc.private_route_table_ids
}

output "public_route_table_ids" {
  description = "IDs of public route tables."
  value       = module.vpc.public_route_table_ids
}

output "s3_vpc_endpoint_id" {
  description = "ID of the S3 gateway VPC endpoint."
  value       = module.vpc_endpoints.endpoints["s3"].id
}
