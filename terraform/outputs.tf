# INTENTIONALLY MINIMAL - candidate should expand

output "vpc_id" {
  value = aws_vpc.main.id
}

output "rds_endpoint" {
  description = "The connection endpoint for the billing database"
  value       = aws_db_instance.billing.endpoint
}

output "rds_arn" {
  description = "The ARN of the billing database"
  value       = aws_db_instance.billing.arn
}

output "s3_bucket_arn" {
  description = "The ARN of the billing exports S3 bucket"
  value       = aws_s3_bucket.billing_exports.arn
}

output "iam_admin_user_arn" {
  description = "The ARN of the admin IAM user"
  value       = aws_iam_user.admin.arn
}
