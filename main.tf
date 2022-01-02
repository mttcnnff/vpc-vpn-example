terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.27"
    }
  }

  required_version = ">= 0.15.5"
}

provider "aws" {
  profile = "default"
  region  = "us-east-1"
}

locals {
  region = "us-east-1"
  az              = "${local.region}a"
  cidr_block      = "10.0.0.0/16"
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
}

resource "aws_vpc" "example_vpc" {
  cidr_block                       = local.cidr_block
  tags = {
    Name = "vpc-vpn-example"
  }
}

resource "aws_subnet" "public" {
  count = length(local.public_subnets)

  vpc_id                          = aws_vpc.example_vpc.id
  cidr_block                      = local.public_subnets[count.index]
  availability_zone               = local.az
  map_public_ip_on_launch         = true

  tags = {
    Name = "${aws_vpc.example_vpc.tags.Name}-public-${count.index}"
  }
}

resource "aws_subnet" "private" {
  count = length(local.private_subnets)

  vpc_id                          = aws_vpc.example_vpc.id
  cidr_block                      = local.private_subnets[count.index]
  availability_zone               = local.az
  map_public_ip_on_launch         = false

  tags = {
    Name = "${aws_vpc.example_vpc.tags.Name}-private-${count.index}"
  }
}

resource "aws_route_table" "public" {
  count = length(local.public_subnets)

  vpc_id = aws_vpc.example_vpc.id

  tags = {
    Name = "${aws_vpc.example_vpc.tags.Name}-public-${count.index}"
  }
}

resource "aws_route_table" "private" {
  count = length(local.private_subnets)

  vpc_id = aws_vpc.example_vpc.id

  tags = {
    Name = "${aws_vpc.example_vpc.tags.Name}-private-${count.index}"
  }
}

resource "aws_route_table_association" "public" {
  count = length(local.public_subnets)

  subnet_id = element(aws_subnet.public.*.id, count.index)
  route_table_id = element(aws_route_table.public.*.id, count.index)
}

resource "aws_route_table_association" "private" {
  count = length(local.private_subnets)

  subnet_id = element(aws_subnet.private.*.id, count.index)
  route_table_id = element(aws_route_table.private.*.id, count.index)
}

resource "aws_internet_gateway" "public_subnet_internet_gateway" {
  vpc_id = aws_vpc.example_vpc.id
}

resource "aws_route" "public_subnet_internet_gateway_egress" {
  count = length(local.public_subnets)

  route_table_id         = element(aws_route_table.public.*.id, count.index)
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.public_subnet_internet_gateway.id

  timeouts {
    create = "5m"
  }
}

resource "aws_eip" "nat" {
  vpc = true

  tags = {
    Name = "${aws_vpc.example_vpc.tags.Name}-nat"
  }
}

resource "aws_nat_gateway" "private_subnet_nat_gateway_egress" {
  allocation_id = aws_eip.nat.id
  subnet_id = aws_subnet.public[0].id
}

resource "aws_route" "private_subnet_nat_gateway_egress" {
  count = length(local.private_subnets)

  route_table_id         = element(aws_route_table.private.*.id, count.index)
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.private_subnet_nat_gateway_egress.id

  timeouts {
    create = "5m"
  }

  depends_on = [aws_internet_gateway.public_subnet_internet_gateway]
}

resource "aws_key_pair" "personal-ssh" {
  key_name   = "personal-ssh"
  public_key = file(pathexpand("~/.ssh/id_rsa.pub"))
}

resource "aws_instance" "public_instance" {
  ami = "ami-0e472ba40eb589f49"

  instance_type = "t2.micro"

  tags = {
    Name = "${aws_vpc.example_vpc.tags.Name}-public"
  }

  subnet_id = aws_subnet.public[0].id

  key_name = aws_key_pair.personal-ssh.key_name
}

resource "aws_instance" "private_instance" {
  ami = "ami-0e472ba40eb589f49" # ubuntu ami

  instance_type = "t2.micro"

  tags = {
    Name = "${aws_vpc.example_vpc.tags.Name}-private"
  }

  subnet_id = aws_subnet.private[0].id

  key_name = aws_key_pair.personal-ssh.key_name
}