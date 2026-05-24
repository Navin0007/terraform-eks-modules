resource "aws_security_group" "vpc_endpoints" {
  name_prefix = "${local.name}-vpc-endpoints-"
  description = "Interface VPC endpoints for private EKS/API access in ${local.name}"
  vpc_id      = module.vpc.vpc_id

  tags = merge(local.common_tags, {
    Name = "${local.name}-vpc-endpoints-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "vpc_endpoints_https_from_vpc" {
  security_group_id = aws_security_group.vpc_endpoints.id
  cidr_ipv4         = var.vpc_cidr
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  description       = "HTTPS from VPC to AWS interface endpoints"
}

resource "aws_vpc_security_group_egress_rule" "vpc_endpoints_egress" {
  security_group_id = aws_security_group.vpc_endpoints.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Endpoint responses"
}
