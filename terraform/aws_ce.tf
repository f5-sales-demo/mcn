# ---------------------------------------------------------
# AWS Customer Edge (EC2 instances, IAM, and ordered dual NICs)
# ---------------------------------------------------------

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

  ami                  = var.aws_ce_ami_id
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

  root_block_device {
    delete_on_termination = true
    encrypted             = true
    volume_size           = 100
    volume_type           = "gp3"
  }

  # Bootstrap is required for a fresh appliance to register. Interface identity
  # remains MAC-bound in SMSv2; these guest device labels are configuration only.
  user_data_replace_on_change = true
  user_data                   = <<-EOF
    #cloud-config
    hostname: ${var.component}-aws-ce-${count.index + 1}
    fqdn: ${var.component}-aws-ce-${count.index + 1}.${var.aws_location}.compute.internal
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

  lifecycle {
    precondition {
      condition     = var.aws_ce_ami_id != null
      error_message = "AWS CE deployment requires an explicit approved aws_ce_ami_id; dynamic AMI selection is not allowed."
    }
  }
}
