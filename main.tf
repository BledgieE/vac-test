resource "aws_vpc" "vpc" {
  cidr_block = var.cidr_block

  tags = {
    Name = var.vpc_name
    
  }
}

resource "aws_subnet" "public_subnets" {
  count = length(data.aws_availability_zones.available.names)

  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = cidrsubnet(var.cidr_block, 8, count.index)  
  map_public_ip_on_launch = true
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)

  tags = {
    Name                    = "public-subnet-${count.index + 1}"
    "kubernetes.io/role/elb" = "1"
  }
}



resource "aws_subnet" "private_subnets" {
  count = length(data.aws_availability_zones.available.names)

  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = cidrsubnet(var.cidr_block, 8, count.index + 100)
  map_public_ip_on_launch = false
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)

  tags = {
    Name                    = "private-subnet-${count.index + 1}"
    "kubernetes.io/role/internal-elb"   = "1"
  }
}


resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "${var.vpc_name}-igw"
  }
}

resource "aws_eip" "nat_gateway_eip" {
  
}

resource "aws_nat_gateway" "nat_gateway" {
  allocation_id = aws_eip.nat_gateway_eip.id
  subnet_id     = element(aws_subnet.public_subnets[*].id, random_integer.random_subnet_index.result)
  
  tags = {
    Name = "${var.vpc_name}-nat-gateway"
  }
}


resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${var.vpc_name}-public-rt"
  }
}

resource "aws_route_table_association" "public_rt_associations" {
  count          = length(aws_subnet.public_subnets)
  subnet_id      = element(aws_subnet.public_subnets[*].id, count.index)
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_default_route_table" "private_route_table" {
  default_route_table_id = aws_vpc.vpc.default_route_table_id
  
  route {
    cidr_block     = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.nat_gateway.id
  }

  tags = {
    Name = "${var.vpc_name}-private-rt"
  }
}

resource "aws_route_table_association" "private_route_association" {
  count    = length(aws_subnet.private_subnets)
  subnet_id = element(aws_subnet.private_subnets[*].id, count.index)
  route_table_id = aws_default_route_table.private_route_table.id
}




resource "random_integer" "random_subnet_index" {
  min = 0
  max = length(aws_subnet.public_subnets) - 1
}
