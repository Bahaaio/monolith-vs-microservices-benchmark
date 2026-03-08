output "monolith_public_ip" {
  description = "Public IP of the monolith application instance"
  value       = module.monolith.public_ip
}

output "monolith_private_ip" {
  description = "Private IP of the monolith application instance"
  value       = module.monolith.private_ip
}

output "jmeter_public_ip" {
  description = "Public IP of the JMeter load generator instance"
  value       = module.jmeter.public_ip
}

output "rds_endpoint" {
  description = "RDS endpoint (hostname:port)"
  value       = module.rds.endpoint
}

output "rds_address" {
  description = "RDS hostname"
  value       = module.rds.address
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = module.alb.alb_dns_name
}

output "ssh_command_monolith" {
  description = "SSH command to connect to the monolith instance"
  value       = "ssh -i ~/.ssh/${var.key_name}.pem ec2-user@${module.monolith.public_ip}"
}

output "ssh_command_jmeter" {
  description = "SSH command to connect to the JMeter instance"
  value       = "ssh -i ~/.ssh/${var.key_name}.pem ec2-user@${module.jmeter.public_ip}"
}
