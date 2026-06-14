output "bucket" {
  description = "Name of the Longhorn backup bucket."
  value       = aws_s3_bucket.backup.id
}

output "region" {
  description = "AWS region of the backup bucket."
  value       = var.region
}

output "backup_target" {
  description = "Longhorn backupTarget URL for this bucket (defaultSettings.backupTarget)."
  value       = "s3://${aws_s3_bucket.backup.id}@${var.region}/"
}

output "access_key_id" {
  description = "Access key id for the Longhorn backup IAM user."
  value       = aws_iam_access_key.longhorn_backup.id
  sensitive   = true
}

output "secret_access_key" {
  description = "Secret access key for the Longhorn backup IAM user."
  value       = aws_iam_access_key.longhorn_backup.secret
  sensitive   = true
}
