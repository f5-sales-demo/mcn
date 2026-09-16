variable "region" {
  description = "AWS region containing the dedicated MCN Terraform state backend."
  type        = string
  default     = "ap-northeast-1"
}

variable "replica_region" {
  description = "AWS region containing the encrypted disaster-recovery replica of the MCN state bucket."
  type        = string
  default     = "us-west-2"
  validation {
    condition     = var.replica_region != var.region
    error_message = "replica_region must differ from the primary backend region."
  }
}

variable "bucket_name" {
  description = "Globally unique, dedicated S3 bucket name for this MCN state backend."
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,48}[a-z0-9]$", var.bucket_name)) && !can(regex("\\.\\.", var.bucket_name))
    error_message = "bucket_name must be a valid 3-50 character lowercase S3 bucket name without adjacent periods so derived replica and log bucket names remain valid."
  }
}

variable "noncurrent_version_retention_days" {
  description = "Number of days to retain noncurrent state versions for recovery."
  type        = number
  default     = 365
  validation {
    condition     = var.noncurrent_version_retention_days >= 30
    error_message = "Retain noncurrent state versions for at least 30 days."
  }
}

variable "access_log_retention_days" {
  description = "Number of days to retain primary and replica S3 server-access logs."
  type        = number
  default     = 365
  validation {
    condition     = var.access_log_retention_days >= 90
    error_message = "Retain state-bucket access logs for at least 90 days."
  }
}
