variable "aws_region" {
  type    = string
  default = "eu-central-1"
}

variable "environment" {
  type    = string
  default = "cell-01"
}

variable "db_username" {
  type    = string
  default = "billing_admin"
}

variable "admin_user_name" {
  type        = string
  default     = "platform-admin"
  description = "INTENTIONALLY BAD: shared admin IAM user"
}
