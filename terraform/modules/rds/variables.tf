variable "identifier" {
  description = "Unique identifier for this RDS instance (e.g. 'db', 'user-db', 'product-db')"
  type        = string
}

variable "instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "allocated_storage" {
  description = "Allocated storage in GB"
  type        = number
  default     = 20
}

variable "db_name" {
  description = "Name of the PostgreSQL database to create"
  type        = string
}

variable "db_user" {
  description = "Master username for the database"
  type        = string
  default     = "benchmark"
}

variable "db_password" {
  description = "Master password for the database"
  type        = string
  default     = "benchmark"
  sensitive   = true
}

variable "subnet_ids" {
  description = "List of subnet IDs for the DB subnet group (need at least 2 AZs)"
  type        = list(string)
}

variable "security_group_ids" {
  description = "List of VPC security group IDs"
  type        = list(string)
}

variable "project_name" {
  description = "Project name used for resource tagging"
  type        = string
}

variable "publicly_accessible" {
  description = "Whether the RDS instance is publicly accessible"
  type        = bool
  default     = false
}

variable "init_sql" {
  description = "SQL content to run after database creation (requires psql on Terraform runner)"
  type        = string
  default     = ""
}
