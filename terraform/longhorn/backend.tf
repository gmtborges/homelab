terraform {
  backend "s3" {
    bucket       = "gmtborges-homelab-tfstate"
    key          = "longhorn/terraform.tfstate"
    region       = "us-east-2"
    encrypt      = true
    use_lockfile = true
  }
}
