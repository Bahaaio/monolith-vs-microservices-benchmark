#!/usr/bin/env bash
# =============================================================================
# cleanup.sh - Tear down benchmark environment
# =============================================================================
# Usage:
#   ./scripts/cleanup.sh              # Stop all Docker containers
#   ./scripts/cleanup.sh monolith     # Stop only monolith
#   ./scripts/cleanup.sh microservices # Stop only microservices
#   ./scripts/cleanup.sh aws          # Terraform destroy
# =============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

TARGET="${1:-all}"

cleanup_monolith() {
  info "Stopping monolith containers..."
  docker compose -f "$PROJECT_DIR/docker-compose-monolith.yml" down -v 2>/dev/null || true
  info "Monolith containers stopped."
}

cleanup_microservices() {
  info "Stopping microservices containers..."
  docker compose -f "$PROJECT_DIR/docker-compose-microservices.yml" down -v 2>/dev/null || true
  info "Microservices containers stopped."
}

cleanup_aws() {
  warn "Destroying AWS infrastructure..."

  if [[ -d "$PROJECT_DIR/terraform/monolith" ]]; then
    info "Destroying monolith infrastructure..."
    (cd "$PROJECT_DIR/terraform/monolith" && terraform destroy -auto-approve) || true
  fi

  if [[ -d "$PROJECT_DIR/terraform/microservices" ]]; then
    info "Destroying microservices infrastructure..."
    (cd "$PROJECT_DIR/terraform/microservices" && terraform destroy -auto-approve) || true
  fi

  info "AWS infrastructure destroyed."
}

case "$TARGET" in
monolith)
  cleanup_monolith
  ;;
microservices)
  cleanup_microservices
  ;;
all)
  cleanup_monolith
  cleanup_microservices
  ;;
aws)
  cleanup_aws
  ;;
*)
  error "Unknown target: $TARGET"
  echo "Usage: $0 <monolith|microservices|all|aws>"
  exit 1
  ;;
esac

info "Cleanup complete."
