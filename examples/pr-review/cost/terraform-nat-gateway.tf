# SCENARIO: Cost impact — redundant NAT Gateways per subnet instead of per AZ
#
# Expected pr-review cost output:
#
#   [COST] aws_nat_gateway.private_b, aws_nat_gateway.private_c — redundant
#     Estimated delta: +$64/month (2 additional NAT Gateways @ ~$32/month each)
#     Severity: HIGH
#     Recommendation: Use one NAT Gateway per AZ (not per subnet). Route both
#     private subnets in the same AZ through the same NAT Gateway.
#
#   [COST] aws_eip.nat_b, aws_eip.nat_c — idle EIPs if NAT Gateways removed
#     Estimated delta: +$7.20/month per idle EIP
#     Severity: LOW

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

# Placeholder subnet/EIP references (would be data sources in real usage)
resource "aws_eip" "nat_a" { domain = "vpc" }
resource "aws_eip" "nat_b" { domain = "vpc" }
resource "aws_eip" "nat_c" { domain = "vpc" }

resource "aws_subnet" "public_a" {
  vpc_id            = var.vpc_id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "eu-central-1a"
}

resource "aws_subnet" "public_b" {
  vpc_id            = var.vpc_id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "eu-central-1b"
}

resource "aws_subnet" "public_c" {
  vpc_id            = var.vpc_id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "eu-central-1c"
}

# ✅ BEFORE — one NAT Gateway per AZ (~$32/month)
resource "aws_nat_gateway" "private_a" {
  allocation_id = aws_eip.nat_a.id
  subnet_id     = aws_subnet.public_a.id
  tags          = { Name = "nat-private-a" }
}

# ❌ AFTER (PR adds these) — one per additional subnet, same AZ (~$96/month total)
resource "aws_nat_gateway" "private_b" {
  allocation_id = aws_eip.nat_b.id
  subnet_id     = aws_subnet.public_b.id # ❌ same AZ as an existing private subnet
  tags          = { Name = "nat-private-b" }
}

resource "aws_nat_gateway" "private_c" {
  allocation_id = aws_eip.nat_c.id
  subnet_id     = aws_subnet.public_c.id # ❌ same AZ as another existing private subnet
  tags          = { Name = "nat-private-c" }
}

# ✅ RECOMMENDED — route both private subnets in each AZ through the single NAT Gateway
# resource "aws_route_table" "private_b" {
#   vpc_id = var.vpc_id
#   route {
#     cidr_block     = "0.0.0.0/0"
#     nat_gateway_id = aws_nat_gateway.private_a.id  # reuse AZ-a NAT if same AZ
#   }
# }
