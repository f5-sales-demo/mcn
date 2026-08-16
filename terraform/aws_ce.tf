# AWS Customer Edge nodes. Each instance belongs to its own F5 Secure Mesh site:
# Route Server ECMP is between independent sites, not nodes hidden inside one
# cluster. The SLO ENI is the Route Server peer address.
locals {
  aws_sites = var.enable_aws ? {
    for index in range(3) : format("%02d", index + 1) => {
      index     = index
      site_name = "${local.aws_site_prefix}-${format("%02d", index + 1)}"
    }
  } : {}
}

data "aws_ssm_parameter" "f5_xc_ami" {
  count = var.enable_aws ? 1 : 0
  name  = "/aws/service/marketplace/prod-wrwzhcymymama/latest"
}

data "aws_ami" "test_client" {
  count       = var.enable_aws ? 1 : 0
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-kernel-6.1-x86_64"]
  }
}

resource "aws_iam_role" "ce" {
  count = var.enable_aws ? 1 : 0
  name  = "${var.component}-aws-ce-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" } }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy" "ce" {
  count = var.enable_aws ? 1 : 0
  name  = "${var.component}-aws-ce-policy"
  role  = aws_iam_role.ce[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action   = ["ec2:DescribeInstances", "ec2:DescribeTags", "autoscaling:DescribeAutoScalingInstances"]
      Effect   = "Allow"
      Resource = "*"
    }]
  })
}

resource "aws_iam_instance_profile" "ce" {
  count = var.enable_aws ? 1 : 0
  name  = "${var.component}-aws-ce-profile"
  role  = aws_iam_role.ce[0].id
  tags  = local.tags
}

# The disposable test client uses Systems Manager Run Command so verification
# never depends on a local private key or an inbound management port.
resource "aws_iam_role" "test_client" {
  count = var.enable_aws ? 1 : 0
  name  = "${var.component}-aws-client-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" } }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "test_client_ssm" {
  count      = var.enable_aws ? 1 : 0
  role       = aws_iam_role.test_client[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "test_client" {
  count = var.enable_aws ? 1 : 0
  name  = "${var.component}-aws-client-profile"
  role  = aws_iam_role.test_client[0].name
  tags  = local.tags
}

resource "aws_network_interface" "slo" {
  for_each          = local.aws_sites
  subnet_id         = aws_subnet.public_slo[each.value.index % 3].id
  security_groups   = [aws_security_group.ce[0].id]
  source_dest_check = false
  tags              = merge(local.tags, { Name = "${var.component}-aws-ce-${each.key}-slo" })
}

resource "aws_network_interface" "sli" {
  for_each          = local.aws_sites
  subnet_id         = aws_subnet.private_sli[each.value.index % 3].id
  security_groups   = [aws_security_group.ce[0].id]
  source_dest_check = false
  tags              = merge(local.tags, { Name = "${var.component}-aws-ce-${each.key}-sli" })
}

resource "aws_eip" "ce" {
  #checkov:skip=CKV2_AWS_19:Public SLO is required for this authorized lab CE.
  for_each          = local.aws_sites
  domain            = "vpc"
  network_interface = aws_network_interface.slo[each.key].id
  tags              = merge(local.tags, { Name = "${var.component}-aws-ce-${each.key}-eip" })
}

resource "aws_instance" "ce" {
  for_each             = local.aws_sites
  ami                  = data.aws_ssm_parameter.f5_xc_ami[0].value
  instance_type        = var.aws_instance_type
  iam_instance_profile = aws_iam_instance_profile.ce[0].name

  network_interface {
    network_interface_id = aws_network_interface.slo[each.key].id
    device_index         = 0
  }
  network_interface {
    network_interface_id = aws_network_interface.sli[each.key].id
    device_index         = 1
  }

  user_data = xcsh_site_cloud_init.aws[each.key].cloud_init_config

  root_block_device {
    delete_on_termination = true
    encrypted             = true
    volume_size           = var.aws_root_volume_size_gb
    volume_type           = "gp3"
  }

  tags = merge(local.tags, {
    Name                                            = each.value.site_name
    "ves-io-site-name"                              = each.value.site_name
    "kubernetes.io/cluster/${each.value.site_name}" = "owned"
  })
}

resource "aws_instance" "test_client" {
  count                  = var.enable_aws ? 1 : 0
  ami                    = data.aws_ami.test_client[0].id
  instance_type          = var.aws_test_client_instance_type
  iam_instance_profile   = aws_iam_instance_profile.test_client[0].name
  subnet_id              = aws_subnet.public_slo[0].id
  vpc_security_group_ids = [aws_security_group.test_client[0].id]
  user_data              = "#cloud-config\npackages: [curl]\n"
  tags                   = merge(local.tags, { Name = "${var.component}-aws-client" })
}

# One Route Server peer per independent CE. The peer is the ENI's actual SLO
# address, never a guessed VPC-router address such as x.x.x.1.
resource "aws_vpc_route_server_peer" "ce" {
  for_each = local.aws_sites

  route_server_endpoint_id = aws_vpc_route_server_endpoint.aws[each.value.index % 2].route_server_endpoint_id
  peer_address             = aws_network_interface.slo[each.key].private_ip
  bgp_options { peer_asn = var.aws_ce_asn }
  tags = merge(local.tags, { Name = "${each.value.site_name}-peer" })
}

resource "xcsh_site_cloud_init" "aws" {
  for_each     = local.aws_sites
  provider_ref = "aws"
  site_name    = xcsh_securemesh_site_v2.aws[each.key].name
}
