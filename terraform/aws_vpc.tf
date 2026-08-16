# ---------------------------------------------------------
# AWS VPC, Subnets, Gateways, Route Tables & Security Groups
# ---------------------------------------------------------

data "aws_availability_zones" "available" {
  count = var.enable_aws ? 1 : 0
  state = "available"
}

resource "aws_vpc" "aws" {
  #checkov:skip=CKV2_AWS_11:Lab VPC - flow logging not required
  #checkov:skip=CKV2_AWS_12:Lab VPC - default security group managed by AWS
  count = var.enable_aws ? 1 : 0

  cidr_block           = var.aws_vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.tags, {
    Name = "${var.component}-aws-vpc"
  })
}

resource "aws_internet_gateway" "aws" {
  count = var.enable_aws ? 1 : 0

  vpc_id = aws_vpc.aws[0].id

  tags = merge(local.tags, {
    Name = "${var.component}-aws-igw"
  })
}

# 3 Public SLO Subnets (10.150.1.0/24, 10.150.2.0/24, 10.150.3.0/24)
resource "aws_subnet" "public_slo" {
  count = var.enable_aws ? 3 : 0

  vpc_id                  = aws_vpc.aws[0].id
  cidr_block              = cidrsubnet(var.aws_vpc_cidr, 8, count.index + 1)
  availability_zone       = try(data.aws_availability_zones.available[0].names[count.index], "${var.aws_location}${element(["a", "b", "c"], count.index)}")
  map_public_ip_on_launch = true

  tags = merge(local.tags, {
    Name = "${var.component}-aws-slo-subnet-${count.index + 1}"
  })
}

# 3 Private SLI Subnets (10.150.11.0/24, 10.150.12.0/24, 10.150.13.0/24)
resource "aws_subnet" "private_sli" {
  count = var.enable_aws ? 3 : 0

  vpc_id            = aws_vpc.aws[0].id
  cidr_block        = cidrsubnet(var.aws_vpc_cidr, 8, count.index + 11)
  availability_zone = try(data.aws_availability_zones.available[0].names[count.index], "${var.aws_location}${element(["a", "b", "c"], count.index)}")

  tags = merge(local.tags, {
    Name = "${var.component}-aws-sli-subnet-${count.index + 1}"
  })
}

# Route Server endpoints are AWS-managed ENIs. Keeping them in dedicated
# subnets makes the peering boundary obvious and leaves the CE SLO subnets for
# appliances only.
resource "aws_subnet" "route_server" {
  count = var.enable_aws ? 2 : 0

  vpc_id            = aws_vpc.aws[0].id
  cidr_block        = cidrsubnet(var.aws_vpc_cidr, 8, count.index + 21)
  availability_zone = try(data.aws_availability_zones.available[0].names[count.index], "${var.aws_location}${element(["a", "b"], count.index)}")

  tags = merge(local.tags, {
    Name = "${var.component}-aws-route-server-${count.index + 1}"
  })
}

resource "aws_route_table" "public" {
  count = var.enable_aws ? 1 : 0

  vpc_id = aws_vpc.aws[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.aws[0].id
  }

  tags = merge(local.tags, {
    Name = "${var.component}-aws-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  count = var.enable_aws ? 3 : 0

  subnet_id      = aws_subnet.public_slo[count.index].id
  route_table_id = aws_route_table.public[0].id
}

resource "aws_route_table" "private" {
  count = var.enable_aws ? 1 : 0

  vpc_id = aws_vpc.aws[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.aws[0].id
  }

  tags = merge(local.tags, {
    Name = "${var.component}-aws-private-rt"
  })
}

resource "aws_route_table_association" "private" {
  count = var.enable_aws ? 3 : 0

  subnet_id      = aws_subnet.private_sli[count.index].id
  route_table_id = aws_route_table.private[0].id
}

resource "aws_vpc_route_server" "aws" {
  count           = var.enable_aws ? 1 : 0
  amazon_side_asn = var.aws_route_server_asn
  tags            = merge(local.tags, { Name = "${var.component}-aws-route-server" })
}

resource "aws_vpc_route_server_vpc_association" "aws" {
  count           = var.enable_aws ? 1 : 0
  route_server_id = aws_vpc_route_server.aws[0].route_server_id
  vpc_id          = aws_vpc.aws[0].id
}

resource "aws_vpc_route_server_endpoint" "aws" {
  count           = var.enable_aws ? 2 : 0
  route_server_id = aws_vpc_route_server.aws[0].route_server_id
  subnet_id       = aws_subnet.route_server[count.index].id
  tags            = merge(local.tags, { Name = "${var.component}-aws-rs-endpoint-${count.index + 1}" })

  depends_on = [aws_vpc_route_server_vpc_association.aws]
}

# Dynamic route installation is explicit. Without propagation the Route Server
# can learn the VIP but the test client never receives a usable VPC route.
resource "aws_vpc_route_server_propagation" "aws" {
  for_each = var.enable_aws ? {
    public  = aws_route_table.public[0].id
    private = aws_route_table.private[0].id
  } : {}

  route_server_id = aws_vpc_route_server.aws[0].route_server_id
  route_table_id  = each.value

  depends_on = [aws_vpc_route_server_vpc_association.aws]
}

resource "aws_security_group" "ce" {
  count = var.enable_aws ? 1 : 0

  name        = "${var.component}-aws-ce-sg"
  description = "Security group for F5 XC Customer Edge nodes in AWS"
  vpc_id      = aws_vpc.aws[0].id

  ingress {
    description = "BGP peering"
    from_port   = 179
    to_port     = 179
    protocol    = "tcp"
    cidr_blocks = [var.aws_vpc_cidr]
  }

  ingress {
    description = "ICMP"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [var.aws_vpc_cidr]
  }

  ingress {
    description = "Advertised HTTP VIP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.aws_vpc_cidr]
  }

  ingress {
    description = "Intra-cluster communication"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${var.component}-aws-ce-sg"
  })
}

resource "aws_security_group" "test_client" {
  count       = var.enable_aws ? 1 : 0
  name        = "${var.component}-aws-client-sg"
  description = "Security group for the AWS Route Server test client"
  vpc_id      = aws_vpc.aws[0].id

  egress {
    description = "HTTP and Route Server verification traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${var.component}-aws-client-sg" })
}
