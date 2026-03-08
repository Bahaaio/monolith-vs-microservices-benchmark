variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for the ALB"
  type        = list(string)
}

variable "security_group_ids" {
  description = "List of security group IDs for the ALB"
  type        = list(string)
}

variable "project_name" {
  description = "Project name used for tagging"
  type        = string
}

variable "health_check_path" {
  description = "Path for target group health check"
  type        = string
  default     = "/actuator/health"
}

variable "target_port" {
  description = "Port the target group forwards to"
  type        = number
  default     = 8080
}
