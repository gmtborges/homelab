resource "aws_iam_user" "longhorn_backup" {
  name = var.iam_user_name

  tags = merge(var.tags, { Name = var.iam_user_name })
}

data "aws_iam_policy_document" "longhorn_backup" {
  statement {
    sid       = "LonghornBackupBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [aws_s3_bucket.backup.arn]
  }

  statement {
    sid    = "LonghornBackupObjects"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts",
    ]
    resources = ["${aws_s3_bucket.backup.arn}/*"]
  }
}

resource "aws_iam_user_policy" "longhorn_backup" {
  name   = "${var.iam_user_name}-pol"
  user   = aws_iam_user.longhorn_backup.name
  policy = data.aws_iam_policy_document.longhorn_backup.json
}

resource "aws_iam_access_key" "longhorn_backup" {
  user = aws_iam_user.longhorn_backup.name
}
