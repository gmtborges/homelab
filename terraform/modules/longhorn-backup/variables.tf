variable "bucket_name" {
  description = "Name of the S3 bucket that stores Longhorn volume backups."
  type        = string

  validation {
    condition     = trimspace(var.bucket_name) != ""
    error_message = "bucket_name must be non-empty."
  }
}

variable "iam_user_name" {
  description = "Name of the dedicated IAM user Longhorn uses to reach the backup bucket."
  type        = string

  validation {
    condition     = trimspace(var.iam_user_name) != ""
    error_message = "iam_user_name must be non-empty."
  }
}

variable "region" {
  description = "AWS region for the backup bucket (matches the Longhorn backup target URL)."
  type        = string
  default     = "us-east-2"
}

variable "tags" {
  description = "Tags applied to taggable resources, merged with a per-resource Name tag."
  type        = map(string)
  default     = {}
}
