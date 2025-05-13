terraform {
  backend "s3" {
    bucket = "terraform-state-homelab"
    key    = "standalone-vms/terraform.tfstate"
    region = "us-east-2"
  }
}
