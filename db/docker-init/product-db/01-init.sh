#!/bin/bash
# Product DB init: create products table and seed product data
set -e

SQL_DIR="/sql"

echo "Initializing product database..."

echo "Creating products table..."
psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f "$SQL_DIR/create-products.sql"

echo "Seeding products..."
psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f "$SQL_DIR/seed-products.sql"

echo "Product database initialization complete."
