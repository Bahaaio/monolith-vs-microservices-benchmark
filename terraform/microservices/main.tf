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
# Databases (RDS PostgreSQL — one per microservice)
################################################################################

module "user_db" {
  source = "../modules/rds"

  identifier         = "user-db"
  instance_class     = var.db_instance_class
  subnet_ids         = module.vpc.public_subnet_ids
  security_group_ids = [module.sg.db_sg_id]
  project_name       = var.project_name
  db_name            = "userdb"
  db_user            = var.db_user
  db_password        = var.db_password

  init_sql = join("\n", [
    file("${path.module}/../../db/sql/create-users.sql"),
    file("${path.module}/../../db/sql/seed-users.sql"),
  ])
}

module "product_db" {
  source = "../modules/rds"

  identifier         = "product-db"
  instance_class     = var.db_instance_class
  subnet_ids         = module.vpc.public_subnet_ids
  security_group_ids = [module.sg.db_sg_id]
  project_name       = var.project_name
  db_name            = "productdb"
  db_user            = var.db_user
  db_password        = var.db_password

  init_sql = join("\n", [
    file("${path.module}/../../db/sql/create-products.sql"),
    file("${path.module}/../../db/sql/seed-products.sql"),
  ])
}

module "order_db" {
  source = "../modules/rds"

  identifier         = "order-db"
  instance_class     = var.db_instance_class
  subnet_ids         = module.vpc.public_subnet_ids
  security_group_ids = [module.sg.db_sg_id]
  project_name       = var.project_name
  db_name            = "orderdb"
  db_user            = var.db_user
  db_password        = var.db_password

  init_sql = join("\n", [
    file("${path.module}/../../db/sql/create-orders.sql"),
    file("${path.module}/../../db/sql/seed-orders.sql"),
  ])
}

################################################################################
# User Service (Spring Boot on EC2)
################################################################################

module "user_service" {
  source = "../modules/ec2"

  instance_type      = var.service_instance_type
  subnet_id          = module.vpc.public_subnet_ids[0]
  security_group_ids = [module.sg.app_sg_id]
  key_name           = var.key_name
  project_name       = var.project_name
  role_name          = "user-service"

  user_data = <<-EOF
#!/bin/bash
set -euo pipefail
exec > /var/log/user-service-setup.log 2>&1

# ── Install Java 17 (Amazon Corretto) and AWS CLI ──────────────────────────
dnf install -y java-17-amazon-corretto-headless aws-cli

# ── Download the application JAR from S3 ───────────────────────────────────
mkdir -p /opt/user-service
aws s3 cp "${var.user_service_jar_s3_url}" /opt/user-service/app.jar

# ── Wait for the RDS database to be ready ──────────────────────────────────
DB_HOST="${module.user_db.address}"
DB_PORT=${module.user_db.port}
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
cat > /etc/systemd/system/user-service.service <<'UNIT'
[Unit]
Description=User Service Spring Boot Application
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/opt/user-service

Environment="SPRING_DATASOURCE_URL=jdbc:postgresql://${module.user_db.address}:${module.user_db.port}/userdb"
Environment="SPRING_DATASOURCE_USERNAME=${var.db_user}"
Environment="SPRING_DATASOURCE_PASSWORD=${var.db_password}"
Environment="SERVER_PORT=8080"
Environment="JAVA_OPTS=-Xms256m -Xmx512m"

ExecStart=/usr/bin/java $JAVA_OPTS -jar /opt/user-service/app.jar
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
UNIT

# ── Start the service ─────────────────────────────────────────────────────
chown -R ec2-user:ec2-user /opt/user-service
systemctl daemon-reload
systemctl enable user-service
systemctl start user-service
EOF
}

################################################################################
# Product Service (Spring Boot on EC2)
################################################################################

module "product_service" {
  source = "../modules/ec2"

  instance_type      = var.service_instance_type
  subnet_id          = module.vpc.public_subnet_ids[0]
  security_group_ids = [module.sg.app_sg_id]
  key_name           = var.key_name
  project_name       = var.project_name
  role_name          = "product-service"

  user_data = <<-EOF
#!/bin/bash
set -euo pipefail
exec > /var/log/product-service-setup.log 2>&1

# ── Install Java 17 (Amazon Corretto) and AWS CLI ──────────────────────────
dnf install -y java-17-amazon-corretto-headless aws-cli

# ── Download the application JAR from S3 ───────────────────────────────────
mkdir -p /opt/product-service
aws s3 cp "${var.product_service_jar_s3_url}" /opt/product-service/app.jar

# ── Wait for the RDS database to be ready ──────────────────────────────────
DB_HOST="${module.product_db.address}"
DB_PORT=${module.product_db.port}
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
cat > /etc/systemd/system/product-service.service <<'UNIT'
[Unit]
Description=Product Service Spring Boot Application
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/opt/product-service

Environment="SPRING_DATASOURCE_URL=jdbc:postgresql://${module.product_db.address}:${module.product_db.port}/productdb"
Environment="SPRING_DATASOURCE_USERNAME=${var.db_user}"
Environment="SPRING_DATASOURCE_PASSWORD=${var.db_password}"
Environment="SERVER_PORT=8080"
Environment="JAVA_OPTS=-Xms256m -Xmx512m"

ExecStart=/usr/bin/java $JAVA_OPTS -jar /opt/product-service/app.jar
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
UNIT

# ── Start the service ─────────────────────────────────────────────────────
chown -R ec2-user:ec2-user /opt/product-service
systemctl daemon-reload
systemctl enable product-service
systemctl start product-service
EOF
}

################################################################################
# Order Service (Spring Boot on EC2)
################################################################################

module "order_service" {
  source = "../modules/ec2"

  instance_type      = var.service_instance_type
  subnet_id          = module.vpc.public_subnet_ids[0]
  security_group_ids = [module.sg.app_sg_id]
  key_name           = var.key_name
  project_name       = var.project_name
  role_name          = "order-service"

  user_data = <<-EOF
#!/bin/bash
set -euo pipefail
exec > /var/log/order-service-setup.log 2>&1

# ── Install Java 17 (Amazon Corretto) and AWS CLI ──────────────────────────
dnf install -y java-17-amazon-corretto-headless aws-cli

# ── Download the application JAR from S3 ───────────────────────────────────
mkdir -p /opt/order-service
aws s3 cp "${var.order_service_jar_s3_url}" /opt/order-service/app.jar

# ── Wait for the RDS database to be ready ──────────────────────────────────
DB_HOST="${module.order_db.address}"
DB_PORT=${module.order_db.port}
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
cat > /etc/systemd/system/order-service.service <<'UNIT'
[Unit]
Description=Order Service Spring Boot Application
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/opt/order-service

Environment="SPRING_DATASOURCE_URL=jdbc:postgresql://${module.order_db.address}:${module.order_db.port}/orderdb"
Environment="SPRING_DATASOURCE_USERNAME=${var.db_user}"
Environment="SPRING_DATASOURCE_PASSWORD=${var.db_password}"
Environment="USER_SERVICE_URL=http://${module.user_service.private_ip}:8080"
Environment="PRODUCT_SERVICE_URL=http://${module.product_service.private_ip}:8080"
Environment="SERVER_PORT=8080"
Environment="JAVA_OPTS=-Xms256m -Xmx512m"

ExecStart=/usr/bin/java $JAVA_OPTS -jar /opt/order-service/app.jar
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
UNIT

# ── Start the service ─────────────────────────────────────────────────────
chown -R ec2-user:ec2-user /opt/order-service
systemctl daemon-reload
systemctl enable order-service
systemctl start order-service
EOF
}

################################################################################
# API Gateway (Spring Cloud Gateway on EC2)
################################################################################

module "gateway" {
  source = "../modules/ec2"

  instance_type      = var.service_instance_type
  subnet_id          = module.vpc.public_subnet_ids[0]
  security_group_ids = [module.sg.app_sg_id]
  key_name           = var.key_name
  project_name       = var.project_name
  role_name          = "gateway"

  user_data = <<-EOF
#!/bin/bash
set -euo pipefail
exec > /var/log/gateway-setup.log 2>&1

# ── Install Java 17 (Amazon Corretto) and AWS CLI ──────────────────────────
dnf install -y java-17-amazon-corretto-headless aws-cli

# ── Download the application JAR from S3 ───────────────────────────────────
mkdir -p /opt/gateway
aws s3 cp "${var.gateway_jar_s3_url}" /opt/gateway/app.jar

# ── Wait for backend services to be ready ──────────────────────────────────
for svc_ip in ${module.user_service.private_ip} ${module.product_service.private_ip} ${module.order_service.private_ip}; do
  echo "Waiting for service at $svc_ip:8080 ..."
  for i in $(seq 1 60); do
    if timeout 2 bash -c "echo > /dev/tcp/$svc_ip/8080" 2>/dev/null; then
      echo "Service at $svc_ip is ready."
      break
    fi
    echo "Attempt $i/60 - $svc_ip not ready, retrying in 5s..."
    sleep 5
  done
done

# ── Create systemd service ─────────────────────────────────────────────────
cat > /etc/systemd/system/gateway.service <<'UNIT'
[Unit]
Description=API Gateway Spring Cloud Gateway Application
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/opt/gateway

Environment="USER_SERVICE_URL=http://${module.user_service.private_ip}:8080"
Environment="PRODUCT_SERVICE_URL=http://${module.product_service.private_ip}:8080"
Environment="ORDER_SERVICE_URL=http://${module.order_service.private_ip}:8080"
Environment="SERVER_PORT=8080"
Environment="JAVA_OPTS=-Xms256m -Xmx512m"

ExecStart=/usr/bin/java $JAVA_OPTS -jar /opt/gateway/app.jar
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
UNIT

# ── Start the service ─────────────────────────────────────────────────────
chown -R ec2-user:ec2-user /opt/gateway
systemctl daemon-reload
systemctl enable gateway
systemctl start gateway
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
# Application Load Balancer (routes to gateway as single entry point)
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
# Target Group Attachment (ALB -> Gateway)
################################################################################

resource "aws_lb_target_group_attachment" "gateway" {
  target_group_arn = module.alb.target_group_arn
  target_id        = module.gateway.instance_id
  port             = 8080
}
