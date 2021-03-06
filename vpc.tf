locals {
  # the default VPC has a network mask of 16 bits
  # so when subnet mask has 4 bits, there are 32 - 16 - 4 = 12 bits left for the host ID
  # Each subnet can support (2^12 - 1) hosts/ENIs
  NO_BITS_SUBNET_MASK = 4
}

# Retrieve existing, default VPC
data "aws_vpc" "default_vpc" {
  default = true
}

data "aws_availability_zones" "az" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

resource "aws_subnet" "public" {
  count  = 3
  vpc_id = data.aws_vpc.default_vpc.id

  cidr_block = cidrsubnet(
    data.aws_vpc.default_vpc.cidr_block,
    local.NO_BITS_SUBNET_MASK,
    count.index
  )

  availability_zone_id = data.aws_availability_zones.az.zone_ids[count.index]

  tags = {
    Name = format("Public_Subnet-%d", count.index)
  }
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id          = data.aws_vpc.default_vpc.id
  service_name    = "com.amazonaws.${data.aws_region.current.name}.dynamodb"
  route_table_ids = [data.aws_vpc.default_vpc.main_route_table_id]
}