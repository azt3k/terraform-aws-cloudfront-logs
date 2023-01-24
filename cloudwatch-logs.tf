data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}
data "aws_iam_policy_document" "kms_log_access" {
  policy_id = "key-policy-cloudwatch"
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
    sid = "AllowCloudWatchLogs"
    actions = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
    effect = "Allow"
    principals {
      type = "Service"
      identifiers = [format("logs.%s.amazonaws.com", data.aws_region.current.name)]
    }
    resources = ["*"]
  }
}

resource "aws_kms_key" "logs" {
  count = var.enable_data_encryption ? 1 : 0
  description = "This key is used to encrypt aws_cloudwatch_log_group.logs objects"
  deletion_window_in_days = 7
  policy = data.aws_iam_policy_document.kms_log_access.json
}

resource "aws_cloudwatch_log_group" "logs" {
  name = var.name
  retention_in_days = var.retention
  tags = var.tags
  kms_key_id = var.enable_data_encryption ? aws_kms_key.logs[0].arn : null
  depends_on  = [
    aws_kms_key.logs
  ]
}

data "aws_iam_policy_document" "logs_cloudwatch_log_group" {
  statement {
    actions   = ["logs:DescribeLogStreams"]
    resources = ["arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"]
  }
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.logs.arn}:*"]
  }
}

resource "aws_kms_key" "lambda" {
  count = var.enable_data_encryption ? 1 : 0
  description = "This key is used to encrypt aws_cloudwatch_log_group.lambda objects"
  deletion_window_in_days = 7
  policy = data.aws_iam_policy_document.kms_log_access.json
}

resource "aws_cloudwatch_log_group" "lambda" {
  name = "/aws/lambda/${var.name}"
  retention_in_days = 3
  tags = var.tags
  kms_key_id = var.enable_data_encryption ? aws_kms_key.lambda[0].arn : null
  depends_on  = [
    aws_kms_key.lambda
  ]
}

data "aws_iam_policy_document" "lambda_cloudwatch_log_group" {
  statement {
    actions   = ["logs:DescribeLogStreams"]
    resources = ["arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"]
  }
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.lambda.arn}:*"]
  }
}
