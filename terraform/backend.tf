terraform {
  # S3 remote state, configured as a PARTIAL backend: no account-specific
  # values are hardcoded here. Create the dedicated bucket with
  # bootstrap/state-backend first, then supply backend.hcl at init time.
  #
  #   Local: terraform init -backend-config=backend.hcl   (copy backend.hcl.example; gitignored)
  #   CI:    terraform init -backend=false                (no state; config-validity + plan tests only)
  #
  # S3 native locking is enabled in backend.hcl; no DynamoDB lock table is
  # required. Authenticate with short-lived AWS credentials, never access keys
  # committed in a backend file.
  backend "s3" {}
}
