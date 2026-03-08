#!/bin/bash
# Monolith DB init: create all tables and seed all data
set -e

SQL_DIR="/sql"

echo "Initializing monolith database..."

echo "Creating users table..."
psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f "$SQL_DIR/create-users.sql"

echo "Creating products table..."
psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f "$SQL_DIR/create-products.sql"

echo "Creating orders table..."
psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f "$SQL_DIR/create-orders.sql"

echo "Seeding users..."
psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f "$SQL_DIR/seed-users.sql"

echo "Seeding products..."
psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f "$SQL_DIR/seed-products.sql"

echo "Seeding orders..."
psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f "$SQL_DIR/seed-orders.sql"

echo "Monolith database initialization complete."
