#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
backend="$repo_root/terraform/backend.tf"
example="$repo_root/terraform/backend.hcl.example"
bootstrap="$repo_root/terraform/bootstrap/state-backend/main.tf"
bootstrap_versions="$repo_root/terraform/bootstrap/state-backend/versions.tf"
variables="$repo_root/terraform/bootstrap/state-backend/variables.tf"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
require() { grep -Fq "$1" "$2" || fail "missing $1 in $2"; }
reject() { ! grep -Fq "$1" "$2" || fail "unexpected $1 in $2"; }

require 'backend "s3" {}' "$backend"
reject 'backend "azurerm"' "$backend"
require 'bucket       = "REPLACE_WITH_BOOTSTRAP_BUCKET"' "$example"
require 'key          = "mcn-ce-ha-smsv2/showcase.tfstate"' "$example"
require 'use_lockfile = true' "$example"
require 'encrypt      = true' "$example"
require 'kms_key_id   = "REPLACE_WITH_BOOTSTRAP_KMS_KEY_ARN"' "$example"
reject 'dynamodb_table' "$example"
reject 'ARM_ACCESS_KEY' "$example"

require 'resource "aws_kms_key" "state"' "$bootstrap"
require 'enable_key_rotation' "$bootstrap"
require 'resource "aws_s3_bucket" "state"' "$bootstrap"
require 'resource "aws_s3_bucket_versioning" "state"' "$bootstrap"
require 'status = "Enabled"' "$bootstrap"
require 'resource "aws_s3_bucket_server_side_encryption_configuration" "state"' "$bootstrap"
require 'aws_kms_key.state.arn' "$bootstrap"
require 'resource "aws_s3_bucket_public_access_block" "state"' "$bootstrap"
require 'block_public_acls       = true' "$bootstrap"
require 'block_public_policy     = true' "$bootstrap"
require 'resource "aws_s3_bucket_ownership_controls" "state"' "$bootstrap"
require 'BucketOwnerEnforced' "$bootstrap"
require 'resource "aws_s3_bucket_lifecycle_configuration" "state"' "$bootstrap"
require 'noncurrent_version_expiration' "$bootstrap"
require 'resource "aws_s3_bucket_policy" "state"' "$bootstrap"
require 'aws:SecureTransport' "$bootstrap"
require 'terraform state only after this bootstrap apply succeeds' "$bootstrap"
require 'variable "bucket_name"' "$variables"
require 'backend "s3" {}' "$bootstrap_versions"

printf 'PASS: AWS state backend is isolated, encrypted, versioned, and lockfile-protected\n'
