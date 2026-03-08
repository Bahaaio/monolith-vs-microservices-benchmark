variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.small"
}

variable "subnet_id" {
  description = "Subnet ID to launch the instance in"
  type        = string
}

variable "security_group_ids" {
  description = "List of security group IDs"
  type        = list(string)
}

variable "key_name" {
  description = "Name of the SSH key pair"
  type        = string
}

variable "user_data" {
  description = "User data script for instance bootstrap"
  type        = string
  default     = null
}

variable "associate_public_ip" {
  description = "Whether to associate a public IP address"
  type        = bool
  default     = true
}

variable "project_name" {
  description = "Project name used for tagging"
  type        = string
}

variable "role_name" {
  description = "Role name for the instance (used in tags)"
  type        = string
}
