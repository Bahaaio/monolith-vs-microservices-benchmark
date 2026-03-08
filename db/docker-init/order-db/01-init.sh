#!/bin/bash
# Order DB init: create orders table and seed order data
set -e

SQL_DIR="/sql"

echo "Initializing order database..."

echo "Creating orders table..."
psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f "$SQL_DIR/create-orders.sql"

echo "Seeding orders..."
psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f "$SQL_DIR/seed-orders.sql"

echo "Order database initialization complete."
