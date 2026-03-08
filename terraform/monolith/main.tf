################################################################################
# Data sources
################################################################################

data "aws_availability_zones" "available" {
  state = "available"
}

################################################################################
# VPC
################################################################################

module "vpc" {
  source = "../modules/vpc"

  project_name = var.project_name
  azs          = slice(data.aws_availability_zones.available.names, 0, 2)
}

################################################################################
# Security Groups
################################################################################

module "sg" {
  source = "../modules/sg"

  vpc_id       = module.vpc.vpc_id
  project_name = var.project_name
}

################################################################################
# Database (RDS PostgreSQL)
################################################################################

module "rds" {
  source = "../modules/rds"

  identifier         = "db"
  instance_class     = var.db_instance_class
  subnet_ids         = module.vpc.public_subnet_ids
  security_group_ids = [module.sg.db_sg_id]
  project_name       = var.project_name
  db_name            = var.db_name
  db_user            = var.db_user
  db_password        = var.db_password

  init_sql = join("\n", [
    file("${path.module}/../../db/sql/create-users.sql"),
    file("${path.module}/../../db/sql/create-products.sql"),
    file("${path.module}/../../db/sql/create-orders.sql"),
    file("${path.module}/../../db/sql/seed-users.sql"),
    file("${path.module}/../../db/sql/seed-products.sql"),
    file("${path.module}/../../db/sql/seed-orders.sql"),
  ])
}

################################################################################
# Monolith Application (Spring Boot on EC2)
################################################################################

module "monolith" {
  source = "../modules/ec2"

  instance_type      = var.monolith_instance_type
  subnet_id          = module.vpc.public_subnet_ids[0]
  security_group_ids = [module.sg.app_sg_id]
  key_name           = var.key_name
  project_name       = var.project_name
  role_name          = "monolith"

  user_data = <<-EOF
#!/bin/bash
set -euo pipefail
exec > /var/log/monolith-setup.log 2>&1

# ── Install Java 17 (Amazon Corretto) and AWS CLI ──────────────────────────
dnf install -y java-17-amazon-corretto-headless aws-cli

# ── Download the application JAR from S3 ───────────────────────────────────
mkdir -p /opt/monolith
aws s3 cp "${var.jar_s3_url}" /opt/monolith/app.jar

# ── Wait for the RDS database to be ready ──────────────────────────────────
DB_HOST="${module.rds.address}"
DB_PORT=${module.rds.port}
echo "Waiting for database at $DB_HOST:$DB_PORT ..."
for i in $(seq 1 60); do
  if timeout 2 bash -c "echo > /dev/tcp/$DB_HOST/$DB_PORT" 2>/dev/null; then
    echo "Database is ready."
    break
  fi
  echo "Attempt $i/60 - database not ready, retrying in 5s..."
  sleep 5
done

# ── Create systemd service ─────────────────────────────────────────────────
cat > /etc/systemd/system/monolith.service <<'UNIT'
[Unit]
Description=Monolith Spring Boot Application
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/opt/monolith

Environment="SPRING_DATASOURCE_URL=jdbc:postgresql://${module.rds.address}:${module.rds.port}/${var.db_name}"
Environment="SPRING_DATASOURCE_USERNAME=${var.db_user}"
Environment="SPRING_DATASOURCE_PASSWORD=${var.db_password}"
Environment="SERVER_PORT=8080"
Environment="JAVA_OPTS=-Xms256m -Xmx512m"

ExecStart=/usr/bin/java $JAVA_OPTS -jar /opt/monolith/app.jar
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
UNIT

# ── Start the service ─────────────────────────────────────────────────────
chown -R ec2-user:ec2-user /opt/monolith
systemctl daemon-reload
systemctl enable monolith
systemctl start monolith
EOF
}

################################################################################
# JMeter Load Generator
################################################################################

module "jmeter" {
  source = "../modules/ec2"

  instance_type      = var.jmeter_instance_type
  subnet_id          = module.vpc.public_subnet_ids[0]
  security_group_ids = [module.sg.app_sg_id]
  key_name           = var.key_name
  project_name       = var.project_name
  role_name          = "jmeter"

  user_data = <<-EOF
#!/bin/bash
set -euo pipefail
exec > /var/log/jmeter-setup.log 2>&1

# ── Install Java 17 (required by JMeter) ──────────────────────────────────
dnf install -y java-17-amazon-corretto-headless

# ── Download and install Apache JMeter 5.6.3 ──────────────────────────────
JMETER_VERSION="5.6.3"
JMETER_URL="https://archive.apache.org/dist/jmeter/binaries/apache-jmeter-$${JMETER_VERSION}.tgz"

curl -fSL "$JMETER_URL" -o /tmp/jmeter.tgz
tar -xzf /tmp/jmeter.tgz -C /opt
ln -s /opt/apache-jmeter-$${JMETER_VERSION} /opt/jmeter
rm -f /tmp/jmeter.tgz

# ── Add JMeter to PATH for all users ──────────────────────────────────────
cat > /etc/profile.d/jmeter.sh <<'PROFILE'
export JMETER_HOME=/opt/jmeter
export PATH="$JMETER_HOME/bin:$PATH"
PROFILE

echo "JMeter $${JMETER_VERSION} installed at /opt/jmeter"
EOF
}

################################################################################
# Application Load Balancer
################################################################################

module "alb" {
  source = "../modules/alb"

  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.public_subnet_ids
  security_group_ids = [module.sg.alb_sg_id]
  project_name       = var.project_name
  health_check_path  = "/actuator/health"
  target_port        = 8080
}

################################################################################
# Target Group Attachment (not handled by the ALB module)
################################################################################

resource "aws_lb_target_group_attachment" "monolith" {
  target_group_arn = module.alb.target_group_arn
  target_id        = module.monolith.instance_id
  port             = 8080
}
