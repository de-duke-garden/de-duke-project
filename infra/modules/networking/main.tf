# De-Duke — Networking module
# Provisions a Multi-AZ VPC per environment, per architecture.md's "Regions" section:
# all compute/data resources spread across at least two Availability Zones.

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.tags, { Name = "${var.environment}-de-duke-vpc" })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.environment}-de-duke-igw" })
}

# Public subnets — one per AZ, for the Application Load Balancer and NAT gateways.
resource "aws_subnet" "public" {
  for_each                = var.availability_zones
  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value.public_cidr
  availability_zone       = each.key
  map_public_ip_on_launch = true
  tags                    = merge(var.tags, { Name = "${var.environment}-public-${each.key}" })
}

# Private subnets — one per AZ, for Fargate tasks and the Primary Database.
resource "aws_subnet" "private" {
  for_each          = var.availability_zones
  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value.private_cidr
  availability_zone = each.key
  tags              = merge(var.tags, { Name = "${var.environment}-private-${each.key}" })
}

resource "aws_eip" "nat" {
  for_each = var.availability_zones
  domain   = "vpc"
  tags     = merge(var.tags, { Name = "${var.environment}-nat-eip-${each.key}" })
}

# One NAT gateway per AZ (not a single shared NAT) so a single-AZ outage never
# takes down outbound connectivity for the other AZ's private subnets.
resource "aws_nat_gateway" "this" {
  for_each      = var.availability_zones
  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.public[each.key].id
  tags          = merge(var.tags, { Name = "${var.environment}-nat-${each.key}" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
  tags = merge(var.tags, { Name = "${var.environment}-public-rt" })
}

resource "aws_route_table_association" "public" {
  for_each       = var.availability_zones
  subnet_id      = aws_subnet.public[each.key].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  for_each = var.availability_zones
  vpc_id   = aws_vpc.this.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this[each.key].id
  }
  tags = merge(var.tags, { Name = "${var.environment}-private-rt-${each.key}" })
}

resource "aws_route_table_association" "private" {
  for_each       = var.availability_zones
  subnet_id      = aws_subnet.private[each.key].id
  route_table_id = aws_route_table.private[each.key].id
}
