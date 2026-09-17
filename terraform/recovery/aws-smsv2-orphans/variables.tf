variable "ownership_manifest_path" {
  description = "Absolute path to a fresh schema-v2 collision manifest produced from the exact historical saved plan."
  type        = string
  nullable    = false
}

variable "source_plan_sha256" {
  description = "Expected sha256 digest, including the sha256: prefix, of the historical plan JSON bound by the manifest."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^sha256:[0-9a-f]{64}$", var.source_plan_sha256))
    error_message = "source_plan_sha256 must be a lowercase sha256 digest with the sha256: prefix."
  }
}

variable "aws_account_id" {
  type     = string
  nullable = false

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must contain exactly 12 digits."
  }
}

variable "aws_region" {
  type     = string
  nullable = false

  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "aws_region must be a valid AWS region name."
  }
}

variable "xc_tenant" {
  type     = string
  nullable = false

  validation {
    condition     = var.xc_tenant == "f5-sales-demo"
    error_message = "Orphan recovery is restricted to the f5-sales-demo tenant."
  }
}

variable "creator_id" {
  type     = string
  nullable = false
}

variable "component" {
  type     = string
  nullable = false
}

variable "deployment_generation" {
  type     = string
  nullable = false

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,30}[a-z0-9])?$", var.deployment_generation))
    error_message = "deployment_generation must be a 1-32 character DNS-style label."
  }
}

variable "recovery_public_key" {
  description = "A syntactically valid public key required only to configure the ignored imported aws_key_pair resource."
  type        = string
  sensitive   = true
  nullable    = false
}

variable "recovery_placeholder_domain" {
  description = "Reserved domain required only to configure the ignored imported HTTP load balancer resource."
  type        = string
  default     = "orphan-recovery.invalid"
}
