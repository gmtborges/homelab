output "longhorn_backup_bucket_name" {
  value = aws_s3_bucket.longhorn_backup_bucket.id
}

output "longhorn_backup_user_access_key" {
  value = aws_iam_access_key.longhorn_backup_user_key.id
}

output "longhorn_backup_user_secret_key" {
  value     = aws_iam_access_key.longhorn_backup_user_key.secret
  sensitive = true
}
