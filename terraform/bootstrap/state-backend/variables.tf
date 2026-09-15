variable "region" {
  description = "AWS region containing the dedicated MCN Terraform state backend."
  type        = string
  default     = "ap-northeast-1"
}

variable "bucket_name" {
  description = "Globally unique, dedicated S3 bucket name for this MCN state backend."
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name)) && !can(regex("\\.\\.", var.bucket_name))
    error_message = "bucket_name must be a valid 3-63 character lowercase S3 bucket name without adjacent periods."
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
