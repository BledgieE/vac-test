data "aws_availability_zones" "available" {}

data "aws_autoscaling_group" "nat_asg" {
  name = aws_autoscaling_group.nat_asg.name
}

data "aws_instance" "nat_instance" {
  filter {
    name   = "tag:aws:autoscaling:groupName"
    values = [aws_autoscaling_group.nat_asg.name]
  }
  depends_on = [aws_autoscaling_group.nat_asg]
}
