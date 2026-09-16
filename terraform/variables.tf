variable "aws_region" {
  description = "AWS Region to deploy resources"
  type        = string
  default     = "us-east-2"
}

variable "db_password" {
  description = "Master password for PostgreSQL RDS instances"
  type        = string
  sensitive   = true
}
