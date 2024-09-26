variable "aws_region" {
  description = "The AWS region to create resources in."
  type        = string
}

variable "vpc_name" {
  description = "The name of the vpc."
  type        = string
}

variable "cidr_block" {
  description = "The CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}