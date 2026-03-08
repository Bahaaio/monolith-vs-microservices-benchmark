variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "key_name" {
  description = "Name of the SSH key pair for EC2 instances"
  type        = string
}

variable "service_instance_type" {
  description = "EC2 instance type for all microservice instances (including gateway)"
  type        = string
  default     = "t3.small"
}

variable "db_instance_class" {
  description = "RDS instance class for each database"
  type        = string
  default     = "db.t3.micro"
}

variable "jmeter_instance_type" {
  description = "EC2 instance type for the JMeter load generator"
  type        = string
  default     = "t3.medium"
}

variable "user_service_jar_s3_url" {
  description = "S3 URL for the pre-built user-service JAR (e.g. s3://my-bucket/user-service.jar)"
  type        = string
  default     = ""
}

variable "product_service_jar_s3_url" {
  description = "S3 URL for the pre-built product-service JAR (e.g. s3://my-bucket/product-service.jar)"
  type        = string
  default     = ""
}

variable "order_service_jar_s3_url" {
  description = "S3 URL for the pre-built order-service JAR (e.g. s3://my-bucket/order-service.jar)"
  type        = string
  default     = ""
}

variable "gateway_jar_s3_url" {
  description = "S3 URL for the pre-built API gateway JAR (e.g. s3://my-bucket/gateway.jar)"
  type        = string
  default     = ""
}

variable "project_name" {
  description = "Project name used for resource tagging"
  type        = string
  default     = "benchmark-microservices"
}

variable "db_user" {
  description = "PostgreSQL database user (shared across all RDS instances)"
  type        = string
  default     = "benchmark"
}

variable "db_password" {
  description = "PostgreSQL database password (shared across all RDS instances)"
  type        = string
  default     = "benchmark"
  sensitive   = true
}
