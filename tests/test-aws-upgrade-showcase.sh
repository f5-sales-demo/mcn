#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)

require_text() {
  local file=$1 text=$2
  grep -Fq -- "$text" "${REPO_ROOT}/${file}" || {
    printf 'missing %s in %s\n' "$text" "$file" >&2
    exit 1
  }
}

reject_text() {
  local file=$1 text=$2
  if grep -Fq -- "$text" "${REPO_ROOT}/${file}"; then
    printf 'unexpected %s in %s\n' "$text" "$file" >&2
    exit 1
  fi
}

require_text terraform/versions.tf 'required_version = ">= 1.16.1"'
require_text terraform/versions.tf 'version = "= 7.4.1"'
require_text terraform/aws_xc.tf 'disable_ha                 = {}'
require_text terraform/aws_xc.tf 'cluster_size = 1'
require_text terraform/aws_xc.tf 'operating_system_version = var.aws_baseline_os_version'
require_text terraform/aws_xc.tf 'volterra_software_version = var.aws_baseline_software_version'
require_text terraform/aws_xc.tf 'name      = "${var.component}-aws-vsite"'
require_text terraform/aws_xc.tf 'virtual_site_with_vip {'
require_text terraform/aws_xc.tf 'ip      = var.aws_vip'
require_text terraform/aws_ce.tf 'xcsh_site_cloud_init.aws'
require_text terraform/aws_xc.tf 'resource "xcsh_token" "aws"'
require_text terraform/aws_xc.tf 'type        = 1'
require_text terraform/aws_xc.tf 'site_name   = xcsh_securemesh_site_v2.aws[each.key].name'
require_text terraform/aws_xc.tf 'provider_ref              = "aws"'
require_text terraform/aws_ce.tf '"{{ .token }}"'
require_text terraform/aws_ce.tf 'aws_ce_site_cloud_init = {'
require_text terraform/aws_ce.tf 'try(xcsh_token.aws[key].uid, "{{ .Token }}")'
require_text terraform/aws_ce.tf 'try(xcsh_token.aws[key].uid, "{{ .token }}")'
require_text terraform/aws_ce.tf 'site_cloud_init = local.aws_ce_site_cloud_init[format("%02d", count.index + 1)]'
require_text terraform/aws_ce.tf '"permissions: 0644"'
require_text terraform/aws_ce.tf '"permissions: \"0644\""'
require_text terraform/aws_ce.tf 'var.aws_ssh_public_key != "" ? var.aws_ssh_public_key : local.ssh_public_key'
reject_text terraform/aws_ce.tf 'aws_site_cloud_init = {'
require_text terraform/cloud-init/ce-node-aws.multipart.tpl 'multipart/mixed'
require_text terraform/cloud-init/ce-node-aws.multipart.tpl 'SLI_MAC='
require_text terraform/cloud-init/ce-node-aws.multipart.tpl 'Content-Type: text/cloud-config'
require_text terraform/cloud-init/ce-node-aws.multipart.tpl '${site_cloud_init}'
require_text terraform/cloud-init/ce-node-aws.multipart.tpl 'Content-Type: text/x-shellscript'
require_text terraform/cloud-init/ce-node-aws.multipart.tpl 'hostnamectl set-hostname "${fqdn}"'
require_text terraform/cloud-init/ce-node-aws.multipart.tpl '/var/home/admin/.ssh/authorized_keys'
require_text terraform/cloud-init/ce-node-aws.multipart.tpl 'nmcli connection modify "$connection" ipv4.never-default yes ipv6.never-default yes'
require_text terraform/cloud-init/ce-node-aws.multipart.tpl 'systemctl try-restart vpm.service'
reject_text terraform/cloud-init/ce-node-aws.multipart.tpl '/etc/vpm/'
require_text terraform/aws_vpc.tf 'resource "aws_vpc" "workload"'
require_text terraform/aws_vpc.tf 'resource "aws_instance" "workload"'
require_text terraform/aws_vpc.tf 'resource "aws_ec2_transit_gateway_vpc_attachment" "workload"'
require_text scripts/aws-smsv2-uat-preflight.sh 'upgrade_invoke_plan_has_resource_changes'
require_text scripts/aws-smsv2-uat-preflight.sh '--candidate-provider-binary'
require_text scripts/aws-smsv2-uat-preflight.sh '--candidate-provider-sha256'
require_text scripts/aws-smsv2-uat-preflight.sh 'provider_sha256'
require_text docs/en/demo/deploy.mdx '--candidate-provider-binary'
require_text docs/en/demo/deploy.mdx 'terraform-provider-xcsh'
require_text terraform/aws_upgrade.tf 'action "xcsh_site_upgrade_sw" "aws"'
require_text terraform/aws_upgrade.tf 'action "xcsh_site_upgrade_os" "aws"'
require_text terraform/aws_upgrade.tf 'data "xcsh_site_upgrade_status" "aws"'
require_text terraform/aws_upgrade.tf 'output "aws_site_upgrade_status"'
require_text terraform/aws_upgrade.tf 'target_converged'
require_text terraform/variables_aws.tf 'default     = "crt-20251002-0027"'
require_text terraform/variables_aws.tf 'default     = "9.2026.10"'
require_text terraform/variables_aws.tf 'default     = "crt-20260201-0179"'
require_text terraform/variables_aws.tf 'default     = "9.2026.17"'
require_text terraform/variables_aws.tf 'default     = "10.151.0.0/16"'
require_text terraform/variables_aws.tf 'default     = "198.51.100.10"'
require_text terraform/variables_aws.tf 'variable "aws_bootstrap_site_keys"'
require_text terraform/variables_aws.tf 'default     = ["01", "02", "03"]'

workload_sg=$(sed -n '/resource "aws_security_group" "workload" {/,/^}/p' "${REPO_ROOT}/terraform/aws_vpc.tf")
if grep -Eq '^[[:space:]]*ingress[[:space:]]*{' <<<"$workload_sg"; then
  printf 'workload SSM client security group must not declare ingress\n' >&2
  exit 1
fi
if grep -Fq 'protocol    = "-1"' <<<"$workload_sg"; then
  printf 'workload SSM client security group must not allow unrestricted egress\n' >&2
  exit 1
fi

printf 'PASS: AWS three-site upgrade showcase contract\n'
