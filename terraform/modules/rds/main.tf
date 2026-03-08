################################################################################
# RDS PostgreSQL Module
################################################################################
# Provisions an AWS RDS PostgreSQL instance and optionally runs init SQL via
# a local-exec provisioner (requires psql on the machine running Terraform).
################################################################################

resource "aws_db_subnet_group" "this" {
  name       = "${var.project_name}-${var.identifier}-subnet-group"
  subnet_ids = var.subnet_ids

  tags = {
    Name = "${var.project_name}-${var.identifier}-subnet-group"
  }
}

resource "aws_db_instance" "this" {
  identifier              = "${var.project_name}-${var.identifier}"
  engine                  = "postgres"
  engine_version          = "15"
  instance_class          = var.instance_class
  allocated_storage       = var.allocated_storage
  storage_type            = "gp3"
  db_name                 = var.db_name
  username                = var.db_user
  password                = var.db_password
  db_subnet_group_name    = aws_db_subnet_group.this.name
  vpc_security_group_ids  = var.security_group_ids
  publicly_accessible     = var.publicly_accessible
  skip_final_snapshot     = true
  backup_retention_period = 0
  multi_az                = false

  # Disable performance insights / enhanced monitoring for cost savings
  performance_insights_enabled = false

  tags = {
    Name = "${var.project_name}-${var.identifier}"
  }
}

################################################################################
# Run init SQL after RDS is available (requires psql on Terraform runner)
################################################################################

resource "null_resource" "init_sql" {
  count = var.init_sql != "" ? 1 : 0

  depends_on = [aws_db_instance.this]

  provisioner "local-exec" {
    command = <<-CMD
      export PGPASSWORD='${var.db_password}'
      echo '${replace(var.init_sql, "'", "'\\''")}' | \
        psql -h ${aws_db_instance.this.address} \
             -p ${aws_db_instance.this.port} \
             -U ${var.db_user} \
             -d ${var.db_name} \
             -f -
    CMD
  }
}
