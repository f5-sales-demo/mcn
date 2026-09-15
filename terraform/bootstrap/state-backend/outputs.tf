output "bucket_name" {
  description = "Dedicated S3 bucket for MCN state."
  value       = aws_s3_bucket.state.bucket
}

output "kms_key_arn" {
  description = "KMS key ARN for root and bootstrap backend.hcl files."
  value       = aws_kms_key.state.arn
}

output "showcase_backend_hcl" {
  description = "Non-secret S3 backend settings for terraform/backend.hcl."
  value = {
    bucket       = aws_s3_bucket.state.bucket
    key          = "mcn-ce-ha-smsv2/showcase.tfstate"
    region       = var.region
    encrypt      = true
    kms_key_id   = aws_kms_key.state.arn
    use_lockfile = true
  }
}

output "bootstrap_backend_hcl" {
  description = "Non-secret S3 backend settings used when migrating this bootstrap state after creation."
  value = {
    bucket       = aws_s3_bucket.state.bucket
    key          = "mcn-ce-ha-smsv2/bootstrap.tfstate"
    region       = var.region
    encrypt      = true
    kms_key_id   = aws_kms_key.state.arn
    use_lockfile = true
  }
}
