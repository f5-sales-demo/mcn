output "bucket_name" {
  description = "Dedicated S3 bucket for MCN state."
  value       = aws_s3_bucket.state.bucket
}

output "kms_key_arn" {
  description = "KMS key ARN for root and bootstrap backend.hcl files."
  value       = aws_kms_key.state.arn
}

output "replica" {
  description = "Cross-region recovery destination for encrypted state object versions."
  value = {
    bucket      = aws_s3_bucket.replica.bucket
    region      = var.replica_region
    kms_key_arn = aws_kms_key.replica.arn
  }
}

output "access_log_buckets" {
  description = "Regional server-access log sinks for the primary and replica state buckets."
  value = {
    primary = aws_s3_bucket.logging.bucket
    replica = aws_s3_bucket.replica_logging.bucket
  }
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
