resource "aws_vpc" "vpc" {
  cidr_block = var.cidr_block

  tags = {
    Name = var.vpc_name
  }
}

# Public Subnets
resource "aws_subnet" "public_subnets" {
  count = var.enable_public_subnets ? length(data.aws_availability_zones.available.names) : 0

  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = cidrsubnet(var.cidr_block, 8, count.index)  
  map_public_ip_on_launch = true
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)

  tags = {
    Name                    = "public-subnet-${count.index + 1}"
    "kubernetes.io/role/elb" = "1"
  }
}

# Internet Gateway (only if public subnets are enabled)
resource "aws_internet_gateway" "igw" {
  count = var.enable_public_subnets ? 1 : 0

  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "${var.vpc_name}-igw"
  }
}

# Public Route Table (only if public subnets are enabled)
resource "aws_route_table" "public_route_table" {
  count = var.enable_public_subnets ? 1 : 0

  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw[0].id
  }

  tags = {
    Name = "${var.vpc_name}-public-rt"
  }
}

# Public Route Table Associations (only if public subnets are enabled)
resource "aws_route_table_association" "public_rt_associations" {
  count          = var.enable_public_subnets ? length(aws_subnet.public_subnets) : 0
  subnet_id      = element(aws_subnet.public_subnets[*].id, count.index)
  route_table_id = aws_route_table.public_route_table[0].id
}

# Private Subnets
resource "aws_subnet" "private_subnets" {
  count = var.enable_private_subnets ? length(data.aws_availability_zones.available.names) : 0

  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = cidrsubnet(var.cidr_block, 8, count.index + 100)
  map_public_ip_on_launch = false
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)

  tags = {
    Name                    = "private-subnet-${count.index + 1}"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# Elastic IP for NAT Gateway (only if NAT Gateway and private subnets are enabled)
resource "aws_eip" "nat_gateway_eip" {
  count = var.enable_private_subnets && var.enable_nat_gateway ? 1 : 0
}

# NAT Gateway (only if private subnets and NAT Gateway are enabled)
resource "aws_nat_gateway" "nat_gateway" {
  count = var.enable_private_subnets && var.enable_nat_gateway ? 1 : 0

  allocation_id = aws_eip.nat_gateway_eip[0].id
  subnet_id     = element(aws_subnet.public_subnets[*].id, random_integer.random_subnet_index[0].result)

  tags = {
    Name = "${var.vpc_name}-nat-gateway"
  }
}

# Private Route Table (only if private subnets are enabled)
resource "aws_default_route_table" "private_route_table" {
  count = var.enable_private_subnets ? 1 : 0

  default_route_table_id = aws_vpc.vpc.default_route_table_id
  
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = var.enable_nat_gateway ? aws_nat_gateway.nat_gateway[0].id : null
  }

  tags = {
    Name = "${var.vpc_name}-private-rt"
  }
}

# Private Route Table Associations (only if private subnets are enabled)
resource "aws_route_table_association" "private_route_association" {
  count          = var.enable_private_subnets ? length(aws_subnet.private_subnets) : 0
  subnet_id      = element(aws_subnet.private_subnets[*].id, count.index)
  route_table_id = aws_default_route_table.private_route_table[0].id
}

# Random Integer for selecting public subnet (used for NAT Gateway)
resource "random_integer" "random_subnet_index" {
  count = var.enable_private_subnets ? 1 : 0
  min = 0
  max = length(aws_subnet.public_subnets) - 1
}