terraform {
  required_version = ">= 0.14"

}

provider "aws" {
  region = var.aws_region
  shared_credentials_files = [ "~/.aws/credentials" ]
}
 