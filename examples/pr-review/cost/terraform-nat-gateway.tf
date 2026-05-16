# SCENARIO: Cost impact — new NAT Gateway per subnet instead of per AZ
#
# A PR adds three NAT Gateways — one per subnet — instead of one per AZ.
# This triples the NAT Gateway cost and adds unnecessary cross-AZ data charges.
#
# Expected output:
#
#   [COST] aws_nat_gateway.private_b, aws_nat_gateway.private_c — redundant NAT Gateways
#     Estimated delta: +$64/month (2 additional NAT Gateways @ ~$32/month each)
#     Severity: HIGH
#     Recommendation: Use one NAT Gateway per AZ (not per subnet). private_b and
#     private_c are in the same AZs as an existing NAT Gateway. Route both private
#     subnets in the same AZ through the same NAT Gateway.
#
#   [COST] aws_eip.nat_b, aws_eip.nat_c — unused Elastic IPs if NAT Gateways removed
#     Estimated delta: +$7.20/month per idle EIP
#     Severity: LOW
#     Recommendation: Remove with the NAT Gateways; idle EIPs are billed.

# ❌ BEFORE — one NAT Gateway per AZ (correct pattern, $32/month)
resource "aws_nat_gateway" "private_a" {
  allocation_id = aws_eip.nat_a.id
  subnet_id     = aws_subnet.public_a.id
  tags          = { Name = "nat-private-a" }
}

# ❌ AFTER — PR adds two more, one per additional subnet (costs $96/month total)
resource "aws_nat_gateway" "private_b" {
  allocation_id = aws_eip.nat_b.id
  subnet_id     = aws_subnet.public_b.id   # same AZ as an existing private subnet
  tags          = { Name = "nat-private-b" }
}

resource "aws_nat_gateway" "private_c" {
  allocation_id = aws_eip.nat_c.id
  subnet_id     = aws_subnet.public_c.id   # same AZ as another existing private subnet
  tags          = { Name = "nat-private-c" }
}

resource "aws_eip" "nat_b" { domain = "vpc" }
resource "aws_eip" "nat_c" { domain = "vpc" }

# ✅ RECOMMENDED — one NAT Gateway per AZ, route both private subnets in that AZ to it
# resource "aws_route_table" "private_b" {
#   vpc_id = aws_vpc.main.id
#   route {
#     cidr_block     = "0.0.0.0/0"
#     nat_gateway_id = aws_nat_gateway.private_a.id  # reuse AZ-a NAT if same AZ
#   }
# }
