output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.this.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "igw_id" {
  description = "ID of the internet gateway"
  value       = aws_internet_gateway.this.id
}
