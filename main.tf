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
  depends_on = [ aws_eip.nat_eip ]

  route {
    cidr_block     = "0.0.0.0/0"
    instance_id    = data.aws_instance.nat_instance.public_ip
  }

  tags = {
    Name = "${var.vpc_name}-private-rt"
  }
}

resource "aws_main_route_table_association" "private_rt_associations" {
  route_table_id = aws_default_route_table.private_route_table.id
  vpc_id         = aws_vpc.vpc.id
}


# Launch Template for NAT Instance
resource "aws_launch_template" "nat_instance_template" {
  name = "nat-instance-template"
  image_id = "ami-0ebfd941bbafe70c6"
  key_name = ""

  instance_type = "t2.micro"  

  network_interfaces {
    associate_public_ip_address = true
    subnet_id                   = aws_subnet.public_subnets[0].id
    security_groups             = [aws_security_group.nat_sg.id]
  }

  instance_market_options {
    market_type = "spot"
    spot_options {
      max_price = "0.01"
      spot_instance_type = "one-time"
    }
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 8  
      volume_type = "gp2"  
      delete_on_termination = true
    }
  }

  user_data = base64encode(<<-EOF
              #!/bin/bash
              echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
              sysctl -p
              iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
              EOF
  )
}



# Auto Scaling Group to manage NAT Spot Instances
resource "aws_autoscaling_group" "nat_asg" {
  desired_capacity     = 1
  max_size             = 1
  min_size             = 1
  vpc_zone_identifier  = [aws_subnet.public_subnets[0].id]

  launch_template {
    id      = aws_launch_template.nat_instance_template.id
    version = "$Latest"
  }

  health_check_grace_period = 300
  health_check_type         = "EC2"
}

# Elastic IP for NAT Instance
resource "aws_eip" "nat_eip" {
  depends_on = [aws_autoscaling_group.nat_asg]
}

# Security group for NAT instance
resource "aws_security_group" "nat_sg" {
  name   = "${var.vpc_name}-nat-sg"
  vpc_id = aws_vpc.vpc.id

  # Allow incoming SSH for management
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow traffic from private subnets
  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [for subnet in aws_subnet.public_subnets : subnet.cidr_block]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.vpc_name}-nat-instance-sg"
  }
}
