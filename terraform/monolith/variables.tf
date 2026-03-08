variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "key_name" {
  description = "Name of the SSH key pair for EC2 instances"
  type        = string
}

variable "monolith_instance_type" {
  description = "EC2 instance type for the monolith application"
  type        = string
  default     = "t3.small"
}

variable "db_instance_class" {
  description = "RDS instance class for the database"
  type        = string
  default     = "db.t3.micro"
}

variable "jmeter_instance_type" {
  description = "EC2 instance type for the JMeter load generator"
  type        = string
  default     = "t3.medium"
}

variable "jar_s3_url" {
  description = "S3 URL for the pre-built monolith JAR (e.g. s3://my-bucket/monolith.jar)"
  type        = string
  default     = ""
}

variable "project_name" {
  description = "Project name used for resource tagging"
  type        = string
  default     = "benchmark-monolith"
}

variable "db_user" {
  description = "PostgreSQL database user"
  type        = string
  default     = "benchmark"
}

variable "db_password" {
  description = "PostgreSQL database password"
  type        = string
  default     = "benchmark"
  sensitive   = true
}

variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "benchmarkdb"
}
