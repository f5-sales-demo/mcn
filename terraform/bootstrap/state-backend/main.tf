# Bootstrap this stack with local state once, using a reviewed saved plan. Do
# not point the showcase at the bucket until this completes. Migrate the
# bootstrap state to bootstrap/terraform.tfstate with `terraform init
# -migrate-state` after the bucket exists; terraform state only after this bootstrap apply succeeds.

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

locals {
  account_root_arn            = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"
  replica_bucket_name         = "${var.bucket_name}-replica"
  logging_bucket_name         = "${var.bucket_name}-logs"
  replica_logging_bucket_name = "${var.bucket_name}-replica-logs"
}

data "aws_iam_policy_document" "replication_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "replication" {
  name               = "${var.bucket_name}-replication"
  assume_role_policy = data.aws_iam_policy_document.replication_assume_role.json
}

# KMS key policies use Resource "*" to mean only the key carrying the policy;
# the principals remain restricted to this account root and the replication role.
data "aws_iam_policy_document" "state_kms" {
  #checkov:skip=CKV_AWS_109: This is a resource-scoped KMS key policy, not an identity policy.
  #checkov:skip=CKV_AWS_111: Key-administration writes are restricted to this account root.
  #checkov:skip=CKV_AWS_356: KMS requires Resource "*" in a policy attached to the key itself.
  statement {
    sid       = "EnableAccountAdministration"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = [local.account_root_arn]
    }
  }

  statement {
    sid = "AllowReplicationUse"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:GenerateDataKey*",
      "kms:ReEncrypt*",
    ]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.replication.arn]
    }
  }
}

data "aws_iam_policy_document" "replica_kms" {
  #checkov:skip=CKV_AWS_109: This is a resource-scoped KMS key policy, not an identity policy.
  #checkov:skip=CKV_AWS_111: Key-administration writes are restricted to this account root.
  #checkov:skip=CKV_AWS_356: KMS requires Resource "*" in a policy attached to the key itself.
  statement {
    sid       = "EnableAccountAdministration"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = [local.account_root_arn]
    }
  }

  statement {
    sid = "AllowReplicationUse"
    actions = [
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:GenerateDataKey*",
      "kms:ReEncrypt*",
    ]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.replication.arn]
    }
  }
}

resource "aws_kms_key" "state" {
  description             = "MCN SMSv2 Terraform state encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.state_kms.json
}

resource "aws_kms_alias" "state" {
  name          = "alias/${var.bucket_name}-terraform-state"
  target_key_id = aws_kms_key.state.key_id
}

resource "aws_kms_key" "replica" {
  provider                = aws.replica
  description             = "MCN SMSv2 replicated Terraform state encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.replica_kms.json
}

resource "aws_kms_alias" "replica" {
  provider      = aws.replica
  name          = "alias/${var.bucket_name}-replica-terraform-state"
  target_key_id = aws_kms_key.replica.key_id
}

resource "aws_s3_bucket" "state" {
  bucket = var.bucket_name
  lifecycle {
    prevent_destroy = true
  }
}

# This is the terminal recovery destination, not another source of truth.
#checkov:skip=CKV_AWS_144: Replicating the replica back to the primary would create a replication cycle.
resource "aws_s3_bucket" "replica" {
  provider = aws.replica
  bucket   = local.replica_bucket_name
  lifecycle {
    prevent_destroy = true
  }
}

# S3 server-access log delivery requires an SSE-S3 destination. The logging
# sink is purpose-specific, receives no application data, and is not recursively
# logged, notified, or replicated.
#checkov:skip=CKV_AWS_18: Logging a log-delivery sink would recursively generate access logs.
#checkov:skip=CKV_AWS_144: The primary state bucket, not its access-log sink, is replicated cross-region.
#checkov:skip=CKV_AWS_145: S3 server-access log delivery requires SSE-S3 on the destination bucket.
#checkov:skip=CKV2_AWS_62: EventBridge notifications are enabled on the state bucket, not its log sink.
resource "aws_s3_bucket" "logging" {
  bucket = local.logging_bucket_name
  lifecycle {
    prevent_destroy = true
  }
}

#checkov:skip=CKV_AWS_18: Logging a log-delivery sink would recursively generate access logs.
#checkov:skip=CKV_AWS_144: The replica state bucket, not its access-log sink, is the recovery destination.
#checkov:skip=CKV_AWS_145: S3 server-access log delivery requires SSE-S3 on the destination bucket.
#checkov:skip=CKV2_AWS_62: EventBridge notifications are enabled on the replica state bucket, not its log sink.
resource "aws_s3_bucket" "replica_logging" {
  provider = aws.replica
  bucket   = local.replica_logging_bucket_name
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "replica" {
  provider                = aws.replica
  bucket                  = aws_s3_bucket.replica.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "logging" {
  bucket                  = aws_s3_bucket.logging.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "replica_logging" {
  provider                = aws.replica
  bucket                  = aws_s3_bucket.replica_logging.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_ownership_controls" "replica" {
  provider = aws.replica
  bucket   = aws_s3_bucket.replica.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_ownership_controls" "logging" {
  bucket = aws_s3_bucket.logging.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_ownership_controls" "replica_logging" {
  provider = aws.replica
  bucket   = aws_s3_bucket.replica_logging.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "replica" {
  provider = aws.replica
  bucket   = aws_s3_bucket.replica.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "logging" {
  bucket = aws_s3_bucket.logging.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "replica_logging" {
  provider = aws.replica
  bucket   = aws_s3_bucket.replica_logging.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.state.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "replica" {
  provider = aws.replica
  bucket   = aws_s3_bucket.replica.id
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.replica.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logging" {
  bucket = aws_s3_bucket.logging.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "replica_logging" {
  provider = aws.replica
  bucket   = aws_s3_bucket.replica_logging.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    id     = "retain-state-recovery-history"
    status = "Enabled"
    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_retention_days
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "replica" {
  provider = aws.replica
  bucket   = aws_s3_bucket.replica.id
  rule {
    id     = "retain-state-recovery-history"
    status = "Enabled"
    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_retention_days
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "logging" {
  bucket = aws_s3_bucket.logging.id
  rule {
    id     = "expire-access-logs"
    status = "Enabled"
    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    expiration {
      days = var.access_log_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.access_log_retention_days
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "replica_logging" {
  provider = aws.replica
  bucket   = aws_s3_bucket.replica_logging.id
  rule {
    id     = "expire-access-logs"
    status = "Enabled"
    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    expiration {
      days = var.access_log_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.access_log_retention_days
    }
  }
}

data "aws_iam_policy_document" "state" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.state.arn,
      "${aws_s3_bucket.state.arn}/*",
    ]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

data "aws_iam_policy_document" "replica" {
  provider = aws.replica
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.replica.arn,
      "${aws_s3_bucket.replica.arn}/*",
    ]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

data "aws_iam_policy_document" "logging" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.logging.arn,
      "${aws_s3_bucket.logging.arn}/*",
    ]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  statement {
    sid       = "AllowServerAccessLogs"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.logging.arn}/primary/*"]
    principals {
      type        = "Service"
      identifiers = ["logging.s3.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.state.arn]
    }
  }
}

data "aws_iam_policy_document" "replica_logging" {
  provider = aws.replica
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.replica_logging.arn,
      "${aws_s3_bucket.replica_logging.arn}/*",
    ]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  statement {
    sid       = "AllowServerAccessLogs"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.replica_logging.arn}/replica/*"]
    principals {
      type        = "Service"
      identifiers = ["logging.s3.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.replica.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = data.aws_iam_policy_document.state.json
}

resource "aws_s3_bucket_policy" "replica" {
  provider = aws.replica
  bucket   = aws_s3_bucket.replica.id
  policy   = data.aws_iam_policy_document.replica.json
}

resource "aws_s3_bucket_policy" "logging" {
  bucket = aws_s3_bucket.logging.id
  policy = data.aws_iam_policy_document.logging.json
}

resource "aws_s3_bucket_policy" "replica_logging" {
  provider = aws.replica
  bucket   = aws_s3_bucket.replica_logging.id
  policy   = data.aws_iam_policy_document.replica_logging.json
}

resource "aws_s3_bucket_logging" "state" {
  bucket        = aws_s3_bucket.state.id
  target_bucket = aws_s3_bucket.logging.id
  target_prefix = "primary/"

  depends_on = [aws_s3_bucket_policy.logging]
}

resource "aws_s3_bucket_logging" "replica" {
  provider      = aws.replica
  bucket        = aws_s3_bucket.replica.id
  target_bucket = aws_s3_bucket.replica_logging.id
  target_prefix = "replica/"

  depends_on = [aws_s3_bucket_policy.replica_logging]
}

resource "aws_s3_bucket_notification" "state" {
  bucket      = aws_s3_bucket.state.id
  eventbridge = true
}

resource "aws_s3_bucket_notification" "replica" {
  provider    = aws.replica
  bucket      = aws_s3_bucket.replica.id
  eventbridge = true
}

data "aws_iam_policy_document" "replication" {
  statement {
    sid = "ReadSourceBucket"
    actions = [
      "s3:GetReplicationConfiguration",
      "s3:ListBucket",
    ]
    resources = [aws_s3_bucket.state.arn]
  }

  statement {
    sid = "ReadSourceVersions"
    actions = [
      "s3:GetObjectVersionAcl",
      "s3:GetObjectVersionForReplication",
      "s3:GetObjectVersionTagging",
    ]
    resources = ["${aws_s3_bucket.state.arn}/*"]
  }

  statement {
    sid = "WriteReplicaVersions"
    actions = [
      "s3:ReplicateDelete",
      "s3:ReplicateObject",
      "s3:ReplicateTags",
    ]
    resources = ["${aws_s3_bucket.replica.arn}/*"]
  }

  statement {
    sid       = "DecryptSourceState"
    actions   = ["kms:Decrypt"]
    resources = [aws_kms_key.state.arn]
  }

  statement {
    sid = "EncryptReplicaState"
    actions = [
      "kms:Encrypt",
      "kms:GenerateDataKey*",
    ]
    resources = [aws_kms_key.replica.arn]
  }
}

resource "aws_iam_role_policy" "replication" {
  name   = "state-replication"
  role   = aws_iam_role.replication.id
  policy = data.aws_iam_policy_document.replication.json
}

resource "aws_s3_bucket_replication_configuration" "state" {
  depends_on = [
    aws_iam_role_policy.replication,
    aws_s3_bucket_versioning.state,
    aws_s3_bucket_versioning.replica,
  ]

  role   = aws_iam_role.replication.arn
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "replicate-encrypted-state"
    status = "Enabled"

    filter {}

    delete_marker_replication {
      status = "Enabled"
    }

    source_selection_criteria {
      sse_kms_encrypted_objects {
        status = "Enabled"
      }
    }

    destination {
      bucket        = aws_s3_bucket.replica.arn
      storage_class = "STANDARD_IA"

      encryption_configuration {
        replica_kms_key_id = aws_kms_key.replica.arn
      }
    }
  }
}
