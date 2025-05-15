locals {
  longhorn_backup_bucket_name = "gmtborges-homelab-longhorn-backup"
}

resource "aws_s3_bucket" "longhorn_backup_bucket" {
  bucket = local.longhorn_backup_bucket_name
}

resource "aws_s3_bucket_versioning" "longhorn_backup_bucket_versioning" {
  bucket = aws_s3_bucket.longhorn_backup_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "longhorn_backup_bucket_encryption" {
  bucket = aws_s3_bucket.longhorn_backup_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "longhorn_backup_bucket_lifecycle" {
  bucket = aws_s3_bucket.longhorn_backup_bucket.id

  rule {
    id     = "cleanup-old-backups"
    status = "Enabled"

    expiration {
      days = 30
    }

    filter {
      prefix = "/"
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

resource "aws_iam_user" "longhorn_backup_user" {
  name = "longhorn-backup-user"
  path = "/"
  tags = {
    Name = "longhorn-backup-user"
  }
}

resource "aws_iam_access_key" "longhorn_backup_user_key" {
  user = aws_iam_user.longhorn_backup_user.name
}

resource "aws_iam_policy" "longhorn_backup_policy" {
  name = "longhorn-backup-policy"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "GrantLonghornBackupstoreAccess0",
        Effect = "Allow",
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:DeleteObject"
        ],
        Resource = [
          "arn:aws:s3:::${local.longhorn_backup_bucket_name}",
          "arn:aws:s3:::${local.longhorn_backup_bucket_name}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_user_policy_attachment" "longhorn_backup_policy_attachment" {
  user       = aws_iam_user.longhorn_backup_user.name
  policy_arn = aws_iam_policy.longhorn_backup_policy.arn
}
