#!/usr/bin/env bash
# =============================================================================
# setup.sh - One-time local development setup
# =============================================================================
# Creates Python .venv and installs shared-lib into your local Maven repo.
# Run this once after cloning, or after changing shared-lib.
#
# Usage:
#   ./scripts/setup.sh
# =============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

# ---------------------------------------------------------------------------
# 1. Python virtual environment
# ---------------------------------------------------------------------------
info "Setting up Python virtual environment..."

if ! command -v python3 &>/dev/null; then
  error "python3 not found. Install Python 3 first."
  exit 1
fi

VENV_DIR="$PROJECT_DIR/.venv"

if [[ -d "$VENV_DIR" ]]; then
  info ".venv already exists, reinstalling dependencies..."
else
  python3 -m venv "$VENV_DIR"
  info "Created .venv at $VENV_DIR"
fi

"$VENV_DIR/bin/pip" install -r "$PROJECT_DIR/python/requirements.txt"

info "Python dependencies installed."

# ---------------------------------------------------------------------------
# 2. Maven: install shared-lib into local repo
# ---------------------------------------------------------------------------
info "Installing shared-lib into local Maven repository..."

if ! command -v mvn &>/dev/null; then
  error "mvn not found. Install Maven first."
  exit 1
fi

mvn -f "$PROJECT_DIR/shared-lib/pom.xml" install -DskipTests

info "shared-lib installed to ~/.m2/repository"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
info "============================================"
info "  Setup complete!"
info "============================================"
info "  Python venv:   $VENV_DIR"
info "  Activate it:   source .venv/bin/activate"
info "  shared-lib:    installed in local Maven repo"
info "============================================"
