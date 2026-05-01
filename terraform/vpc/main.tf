terraform {
  required_version = ">= 1.15.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_availability_zones" "available" {
  state = "available"
}

# VPC
resource "aws_vpc" "beblitech_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "beblitech-prod-vpc"
    Environment = "production"
    Project     = "beblitech-observability"
    ManagedBy   = "terraform"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.beblitech_vpc.id

  tags = {
    Name    = "beblitech-prod-igw"
    Project = "beblitech-observability"
  }
}

# Public Subnets
resource "aws_subnet" "public" {
  count                   = 3
  vpc_id                  = aws_vpc.beblitech_vpc.id
  cidr_block              = "10.0.${count.index + 1}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name                     = "beblitech-public-subnet-${count.index + 1}"
    Type                     = "public"
    Project                  = "beblitech-observability"
    "kubernetes.io/role/elb" = "1"
  }
}

# Private Subnets
resource "aws_subnet" "private" {
  count             = 3
  vpc_id            = aws_vpc.beblitech_vpc.id
  cidr_block        = "10.0.${count.index + 10}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name                              = "beblitech-private-subnet-${count.index + 1}"
    Type                              = "private"
    Project                           = "beblitech-observability"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# Elastic IP for NAT Gateway
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name    = "beblitech-nat-eip"
    Project = "beblitech-observability"
  }
}

# NAT Gateway in first public subnet
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name    = "beblitech-nat-gw"
    Project = "beblitech-observability"
  }

  depends_on = [aws_internet_gateway.igw]
}

# Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.beblitech_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name    = "beblitech-public-rt"
    Project = "beblitech-observability"
  }
}

# Private Route Table
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.beblitech_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name    = "beblitech-private-rt"
    Project = "beblitech-observability"
  }
}

# Public Route Table Associations
resource "aws_route_table_association" "public" {
  count          = 3
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private Route Table Associations
resource "aws_route_table_association" "private" {
  count          = 3
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
