output "bucket_name" {
  description = "Name of the history bucket."
  value       = aws_s3_bucket.history.bucket
}

output "bucket_arn" {
  description = "ARN of the history bucket."
  value       = aws_s3_bucket.history.arn
}
