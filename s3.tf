data "aws_canonical_user_id" "current" {}

data "aws_iam_policy_document" "kms_cdn_s3_access" {
  policy_id = "CDN Key Policy"
  statement {
    sid = "Enable IAM User Permissions"
    actions = ["kms:*"]
    effect = "Allow"
    principals {
      type = "AWS"
      identifiers = [format("arn:%s:iam::%s:root", data.aws_partition.current.partition, data.aws_caller_identity.current.account_id)]
    }
    resources = ["*"]
  }
  statement {
    sid = "Allow CloudFront to use the key to deliver logs"
    actions = ["kms:GenerateDataKey*"]
    effect = "Allow"
    principals {
      type = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }
    resources = ["*"]
  }
  statement {
    sid = "Allow Lambda to use the key to decrypt logs"
    actions = ["kms:Decrypt*"]
    effect = "Allow"
    principals {
      type = "aws"
      identifiers = [format("arn:%s:iam::%s:root", data.aws_partition.current.partition, data.aws_caller_identity.current.account_id)]
    }
    resources = ["*"]
  }
}

resource "aws_s3_bucket" "this" {
  bucket = var.bucket_name
  tags = var.tags
}

resource "aws_kms_key" "this" {
  count = var.enable_data_encryption ? 1 : 0
  description = "This key is used to encrypt aws_s3_bucket.this objects"
  deletion_window_in_days = 7
  policy = data.aws_iam_policy_document.kms_cdn_s3_access.json
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  count = var.enable_data_encryption ? 1 : 0
  bucket = aws_s3_bucket.this.bucket
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.this[0].arn
      sse_algorithm = "aws:kms"
    }
  }
  depends_on = [
    aws_kms_key.this
  ]
}

resource "aws_s3_bucket_acl" "this" {
  bucket = aws_s3_bucket.this.id
  access_control_policy {
    owner {
      id = data.aws_canonical_user_id.current.id
    }
    grant {
      grantee {
        id   = data.aws_canonical_user_id.current.id
        type = "CanonicalUser"
      }
      permission = "FULL_CONTROL"
    }
    grant {
      # Grant CloudFront logs access to your Amazon S3 Bucket
      # https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/AccessLogs.html#AccessLogsBucketAndFileOwnership
      grantee {
        id   = "c4c1ede66af53448b93c283ce9448c4ba468c9432aa01d700d3878632f77d2d0"
        type = "CanonicalUser"
      }
      permission = "FULL_CONTROL"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.bucket
  rule {
    id     = "expiration"
    status = "Enabled"
    expiration {
      days = var.retention
    }
    noncurrent_version_expiration {
      noncurrent_days = 1
    }
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.bucket
  block_public_acls = true
  block_public_policy = true
  ignore_public_acls = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "s3_bucket_readonly" {
  statement {
    actions = [
      "s3:Get*",
      "s3:List*",
    ]
    resources = [
      aws_s3_bucket.this.arn,
      "${aws_s3_bucket.this.arn}/*",
    ]
  }
}

resource "aws_s3_bucket_notification" "this" {
  bucket = aws_s3_bucket.this.bucket
  lambda_function {
    lambda_function_arn = aws_lambda_function.this.arn
    events = ["s3:ObjectCreated:*"]
  }
  depends_on = [aws_lambda_permission.s3_bucket_invoke_function]
}
