output "vpc_id" {
  value = aws_vpc.vpc.id
}

output "public_subnets" {
  value = aws_subnet.public_subnets[*]
}

output "private_subnet" {
  value = aws_subnet.private_subnets[*]
}
