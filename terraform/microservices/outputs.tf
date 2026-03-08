output "user_service_public_ip" {
  description = "Public IP of the user service instance"
  value       = module.user_service.public_ip
}

output "product_service_public_ip" {
  description = "Public IP of the product service instance"
  value       = module.product_service.public_ip
}

output "order_service_public_ip" {
  description = "Public IP of the order service instance"
  value       = module.order_service.public_ip
}

output "gateway_public_ip" {
  description = "Public IP of the API gateway instance"
  value       = module.gateway.public_ip
}

output "gateway_private_ip" {
  description = "Private IP of the API gateway instance (JMeter target)"
  value       = module.gateway.private_ip
}

output "jmeter_public_ip" {
  description = "Public IP of the JMeter load generator instance"
  value       = module.jmeter.public_ip
}

output "user_db_endpoint" {
  description = "RDS endpoint for the user database"
  value       = module.user_db.endpoint
}

output "product_db_endpoint" {
  description = "RDS endpoint for the product database"
  value       = module.product_db.endpoint
}

output "order_db_endpoint" {
  description = "RDS endpoint for the order database"
  value       = module.order_db.endpoint
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer (entry point)"
  value       = module.alb.alb_dns_name
}
