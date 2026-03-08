#!/bin/bash
# User DB init: create users table and seed user data
set -e

SQL_DIR="/sql"

echo "Initializing user database..."

echo "Creating users table..."
psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f "$SQL_DIR/create-users.sql"

echo "Seeding users..."
psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f "$SQL_DIR/seed-users.sql"

echo "User database initialization complete."
