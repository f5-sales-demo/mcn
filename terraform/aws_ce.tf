# ---------------------------------------------------------
# AWS Customer Edge (EC2 instances, IAM, dual-NIC, registration)
# ---------------------------------------------------------

data "aws_ami" "f5_xc" {
  count       = var.enable_aws ? 1 : 0
  most_recent = true
  owners      = ["679593333241", "434481986642", "aws-marketplace"]

  filter {
    name   = "name"
    values = ["f5xc-ce-*", "f5-xc-*", "f5-volterra-*"]
  }
}

resource "aws_key_pair" "ce" {
  count      = var.enable_aws ? 1 : 0
  key_name   = "${var.component}-aws-ce-key"
  public_key = local.ssh_public_key

  tags = local.tags
}

resource "aws_iam_role" "ce" {
  count = var.enable_aws ? 1 : 0
  name  = "${var.component}-aws-ce-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
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
      Action = [
        "ec2:DescribeInstances",
        "ec2:DescribeRouteTables",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeSubnets",
        "ec2:DescribeVpcs"
      ]
      Effect   = "Allow"
      Resource = "*"
    }]
  })
}

resource "aws_iam_instance_profile" "ce" {
  count = var.enable_aws ? 1 : 0
  name  = "${var.component}-aws-ce-profile"
  role  = aws_iam_role.ce[0].id

  tags = local.tags
}

# Dual NICs per Customer Edge node
resource "aws_network_interface" "slo" {
  count = var.enable_aws ? var.aws_ce_count : 0

  subnet_id         = aws_subnet.public_slo[count.index % 3].id
  security_groups   = [aws_security_group.ce[0].id]
  source_dest_check = false

  tags = merge(local.tags, {
    Name = "${var.component}-aws-ce-${count.index + 1}-slo"
  })
}

resource "aws_network_interface" "sli" {
  count = var.enable_aws ? var.aws_ce_count : 0

  subnet_id         = aws_subnet.private_sli[count.index % 3].id
  security_groups   = [aws_security_group.ce[0].id]
  source_dest_check = false

  tags = merge(local.tags, {
    Name = "${var.component}-aws-ce-${count.index + 1}-sli"
  })
}

resource "aws_eip" "ce" {
  #checkov:skip=CKV2_AWS_19:Lab Elastic IP - attached to SLO network interface on CE instance
  count = var.enable_aws ? var.aws_ce_count : 0

  domain            = "vpc"
  network_interface = aws_network_interface.slo[count.index].id

  tags = merge(local.tags, {
    Name = "${var.component}-aws-ce-${count.index + 1}-eip"
  })
}

resource "aws_instance" "ce" {
  count = var.enable_aws ? var.aws_ce_count : 0

  ami                  = data.aws_ami.f5_xc[0].id
  instance_type        = var.aws_instance_type
  iam_instance_profile = aws_iam_instance_profile.ce[0].name
  key_name             = aws_key_pair.ce[0].key_name

  network_interface {
    network_interface_id = aws_network_interface.slo[count.index].id
    device_index         = 0
  }

  network_interface {
    network_interface_id = aws_network_interface.sli[count.index].id
    device_index         = 1
  }

  user_data = <<-EOF
    #cloud-config
    hostname: ${var.component}-aws-ce-${count.index + 1}
    fqdn: ${var.component}-aws-ce-${count.index + 1}.us-east-2.compute.internal
    write_files:
      - path: /etc/vpm/config.yaml
        permissions: '0644'
        content: |
          Vpm:
            ClusterName: aws-site
            ClusterHeader: ""
            Token: ${local.ce_registration_token}
            Latitude: 0
            Longitude: 0
            CertifiedHardwareEndpoint: https://vesio.blob.core.windows.net/releases/certified-hardware/aws.yml
    ssh_authorized_keys:
      - ${chomp(local.ssh_public_key)}
  EOF

  tags = merge(local.tags, {
    Name                             = "${var.component}-aws-ce-${count.index + 1}"
    "ves-io-site-name"               = "aws-site"
    "kubernetes.io/cluster/aws-site" = "owned"
  })
}

# Site registration lookup & automatic approval
data "xcsh_site_registration" "aws" {
  count     = var.enable_aws ? var.aws_ce_count : 0
  site_name = "aws-site"
  namespace = "system"
}

resource "xcsh_registration_approval" "aws" {
  count     = var.enable_aws && length(data.xcsh_site_registration.aws) > 0 && try(data.xcsh_site_registration.aws[0].found, false) ? var.aws_ce_count : 0
  namespace = "system"
  name      = data.xcsh_site_registration.aws[count.index].name
  state     = "APPROVED"
}
