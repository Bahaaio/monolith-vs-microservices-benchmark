#!/usr/bin/env bash
# =============================================================================
# common.sh - Shared utilities for all scripts
# =============================================================================
# Source this file at the top of every script:
#   source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
#
# Provides:
#   - set -euo pipefail
#   - SCRIPT_DIR, PROJECT_DIR, RESULTS_DIR
#   - Color codes (RED, GREEN, YELLOW, BLUE, NC)
#   - info, warn, error, step  (log helpers)
#   - detect_jmeter             (sets JMETER, returns 1 if not found)
#   - detect_python             (sets PYTHON, returns 1 if not found)
#   - TIMESTAMP (YYYY-MM-DD_HH-MM-SS)
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Directories
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RESULTS_DIR="$PROJECT_DIR/results"
mkdir -p "$RESULTS_DIR"

# ---------------------------------------------------------------------------
# Colors & log helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }
step() { echo -e "${BLUE}[STEP]${NC} $*"; }

# ---------------------------------------------------------------------------
# Timestamp (sortable, filesystem-safe)
# ---------------------------------------------------------------------------
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)

# ---------------------------------------------------------------------------
# Tool detection helpers
# ---------------------------------------------------------------------------

# Sets JMETER to the jmeter binary path. Returns 1 if not found.
detect_jmeter() {
  if [[ -n "${JMETER_HOME:-}" ]]; then
    JMETER="$JMETER_HOME/bin/jmeter"
  elif command -v jmeter &>/dev/null; then
    JMETER="jmeter"
  else
    return 1
  fi
}

# Sets PYTHON to the python binary path. Returns 1 if not found.
# Prefers .venv, falls back to system python3.
detect_python() {
  if [[ -x "$PROJECT_DIR/.venv/bin/python" ]]; then
    PYTHON="$PROJECT_DIR/.venv/bin/python"
  elif command -v python3 &>/dev/null; then
    PYTHON="python3"
  else
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Shared analysis function - runs Python visualization on benchmark results
# ---------------------------------------------------------------------------
# Usage:
#   analyze_results <run_dir> <warmup_seconds>
#
# Args:
#   run_dir:         Path to the timestamped run directory (e.g., results/2026-03-08_14-30-00)
#   warmup_seconds:  Number of warmup seconds to discard (default: 0)
#
# Expects:
#   $run_dir/monolith.jtl
#   $run_dir/microservices.jtl
#
# Outputs:
#   $run_dir/charts/
#
# Returns:
#   0 on success, 1 on failure (missing files or directory)
analyze_results() {
  local run_dir="$1"
  local warmup="${2:-0}"

  if [[ ! -d "$run_dir" ]]; then
    error "Run directory not found: $run_dir"
    return 1
  fi

  local mono_file="$run_dir/monolith.jtl"
  local micro_file="$run_dir/microservices.jtl"
  local output_dir="$run_dir/charts"

  step "Running analysis and generating charts..."

  # Both files must exist
  if [[ ! -f "$mono_file" ]]; then
    error "Missing monolith results: $mono_file"
    return 1
  fi

  if [[ ! -f "$micro_file" ]]; then
    error "Missing microservices results: $micro_file"
    return 1
  fi

  # Both files exist — run comparison
  info "Monolith results:       $mono_file"
  info "Microservices results:  $micro_file"

  "$PYTHON" "$PROJECT_DIR/python/visualize.py" \
    --monolith "$mono_file" \
    --microservices "$micro_file" \
    --warmup "$warmup" \
    --output "$output_dir" \
    --results-dir "$run_dir"

  info "Charts saved to: $output_dir/"
}
