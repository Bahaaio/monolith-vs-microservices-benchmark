#!/usr/bin/env bash

# =============================================================================
# run.sh - Run the full benchmark experiment
# =============================================================================
# Builds Docker containers, benchmarks monolith then microservices
# sequentially, then runs analysis and generates charts.
#
# Options (env vars):
#   THREADS=50         Concurrent threads (default: 50)
#   DURATION=60        Test duration in seconds (default: 60)
#   WARMUP=15          Warmup duration in seconds (default: 15)
#   RAMP_UP=5          Ramp-up time in seconds (default: 5)
#   COOL_DOWN=15       Cool-down time between tests in seconds (default: 15)
#   RUNS=5             Number of runs per architecture (default: 5)
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration and constants
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
RESULTS_DIR="$PROJECT_DIR/results"
RUN_DIR="$RESULTS_DIR/$TIMESTAMP"

# required tools
NEEDED=("docker" "jmeter" "uv")

# parameters with defaults
THREADS="${THREADS:-50}"
DURATION="${DURATION:-60}"
WARMUP="${WARMUP:-15}"
RAMP_UP="${RAMP_UP:-5}"
COOL_DOWN="${COOL_DOWN:-15}"
RUNS="${RUNS:-5}"

# ---------------------------------------------------------------------------
# Utility functions
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
# Cleanup trap — tear down any running containers on unexpected exit
# ---------------------------------------------------------------------------

cleanup() {
  warn "Script interrupted. Cleaning up..."

  info "Stopping monolith containers..."
  docker compose -f "$PROJECT_DIR/docker-compose-monolith.yml" down -v 2>/dev/null || true

  info "Stopping microservices containers..."
  docker compose -f "$PROJECT_DIR/docker-compose-microservices.yml" down -v 2>/dev/null || true
}

trap cleanup INT TERM

# ---------------------------------------------------------------------------
# Pre-flight: check required tools
# ---------------------------------------------------------------------------

check_dependencies() {
  MISSING=()

  for tool in "${NEEDED[@]}"; do
    if ! command -v "$tool" &>/dev/null; then
      MISSING+=("$tool")
    fi
  done

  if [[ ${#MISSING[@]} -gt 0 ]]; then
    error "Missing required tools: ${MISSING[*]}"
    exit 1
  fi

  if ! docker info &>/dev/null; then
    error "Docker daemon is not running."
    exit 1
  fi
}

setup() {
  mkdir -p "$RESULTS_DIR"
  mkdir -p "$RUN_DIR"

  info "Setting up Python environment with uv..."
  uv sync --directory "$PROJECT_DIR/python" --quiet

  info "Installing shared-lib into local Maven repository..."
  mvn -f "$PROJECT_DIR/shared-lib/pom.xml" install --quiet -DskipTests
}

print_header() {
  echo ""
  info "============================================"
  info "  Monolith vs Microservices Experiment"
  info "============================================"
  info "  Threads:    $THREADS"
  info "  Duration:   ${DURATION}s"
  info "  Warmup:     ${WARMUP}s"
  info "  Ramp-up:    ${RAMP_UP}s"
  info "  Cool-down:  ${COOL_DOWN}s"
  info "  Runs/Arch:  ${RUNS}"
  info "  Run ID:     $TIMESTAMP"
  info "  Output:     $RUN_DIR"
  info "============================================"
  echo ""
}

# ---------------------------------------------------------------------------
# Helper: run JMeter
# ---------------------------------------------------------------------------
run_jmeter() {
  local arch="$1"
  local host="$2"
  local port="$3"
  local output_file="$4"
  local html_report_dir="$5"

  info "Running JMeter for $arch -> $host:$port"

  jmeter -n \
    -t "$PROJECT_DIR/jmeter/benchmark.jmx" \
    -l "$output_file" \
    -Jhost="$host" \
    -Jport="$port" \
    -Jusers_port="$port" \
    -Jproducts_port="$port" \
    -Jorders_port="$port" \
    -Jthreads="$THREADS" \
    -Jduration="$DURATION" \
    -Jwarmup="$WARMUP" \
    -Jrampup="$RAMP_UP"

  info "JMeter results: $output_file"

  # Quick summary
  if [[ -f "$output_file" ]]; then
    local total_lines
    total_lines=$(wc -l <"$output_file")
    local total_requests=$((total_lines - 1))
    local error_count
    error_count=$(awk -F',' 'NR>1 && $8=="false"{count++} END{print count+0}' "$output_file")
    info "Total requests: $total_requests | Errors: $error_count"
  fi

  # Generate JMeter HTML dashboard
  info "Generating JMeter HTML report -> $html_report_dir"
  jmeter -g "$output_file" -o "$html_report_dir" || warn "HTML report generation failed (non-fatal)"
}

# Analyze results and generate charts using the Python visualization script.
#
# Args:
#   run_dir:         Path to the timestamped run directory
#   warmup_seconds:  Number of warmup seconds to discard (default: 0)
#
analyze_results() {
  local run_dir="$1"
  local warmup="${2:-0}"

  if [[ ! -d "$run_dir" ]]; then
    error "Run directory not found: $run_dir"
    return 1
  fi

  local output_dir="$run_dir/charts"

  step "Running analysis and generating charts..."

  if [[ ! -d "$run_dir/monolith" ]]; then
    error "Missing monolith results directory: $run_dir/monolith"
    return 1
  fi

  if [[ ! -d "$run_dir/microservices" ]]; then
    error "Missing microservices results directory: $run_dir/microservices"
    return 1
  fi

  info "Monolith results directory:       $run_dir/monolith"
  info "Microservices results directory:  $run_dir/microservices"

  uv run --directory "$PROJECT_DIR/python" \
    python visualize.py \
    --experiment-dir "$run_dir" \
    --warmup "$warmup" \
    --output "$output_dir"

  info "Charts saved to: $output_dir/"
}

# ---------------------------------------------------------------------------
# Test monolith
# ---------------------------------------------------------------------------
test_monolith() {
  local arch_dir="$RUN_DIR/monolith"
  mkdir -p "$arch_dir"

  step "===== Testing MONOLITH architecture ($RUNS runs) ====="

  for run in $(seq 1 "$RUNS"); do
    local output_file="$arch_dir/run_${run}.jtl"
    local html_report_dir="$arch_dir/run_${run}_report"

    step "[Monolith] Run $run/$RUNS - cleaning environment..."
    docker compose -f "$PROJECT_DIR/docker-compose-monolith.yml" down -v --remove-orphans 2>/dev/null || true

    step "[Monolith] Run $run/$RUNS - starting stack..."
    docker compose -f "$PROJECT_DIR/docker-compose-monolith.yml" up --wait --build --quiet-build

    step "[Monolith] Run $run/$RUNS - benchmarking..."
    run_jmeter "monolith" "localhost" "8080" "$output_file" "$html_report_dir"

    step "[Monolith] Run $run/$RUNS - stopping stack..."
    docker compose -f "$PROJECT_DIR/docker-compose-monolith.yml" down -v --remove-orphans

    if [[ "$run" -lt "$RUNS" ]]; then
      info "Cooling down for $COOL_DOWN seconds before next monolith run..."
      sleep "$COOL_DOWN"
    fi
  done

  info "Monolith runs complete."
}

# ---------------------------------------------------------------------------
# Test microservices
# ---------------------------------------------------------------------------
test_microservices() {
  local arch_dir="$RUN_DIR/microservices"
  mkdir -p "$arch_dir"

  step "===== Testing MICROSERVICES architecture ($RUNS runs) ====="

  for run in $(seq 1 "$RUNS"); do
    local output_file="$arch_dir/run_${run}.jtl"
    local html_report_dir="$arch_dir/run_${run}_report"

    step "[Microservices] Run $run/$RUNS - cleaning environment..."
    docker compose -f "$PROJECT_DIR/docker-compose-microservices.yml" down -v --remove-orphans 2>/dev/null || true

    step "[Microservices] Run $run/$RUNS - starting stack..."
    docker compose -f "$PROJECT_DIR/docker-compose-microservices.yml" up --wait --build --quiet-build

    step "[Microservices] Run $run/$RUNS - benchmarking..."
    run_jmeter "microservices" "localhost" "8080" "$output_file" "$html_report_dir"

    step "[Microservices] Run $run/$RUNS - stopping stack..."
    docker compose -f "$PROJECT_DIR/docker-compose-microservices.yml" down -v --remove-orphans

    if [[ "$run" -lt "$RUNS" ]]; then
      info "Cooling down for $COOL_DOWN seconds before next microservices run..."
      sleep "$COOL_DOWN"
    fi
  done

  info "Microservices runs complete."
}

main() {
  check_dependencies
  setup
  print_header

  test_monolith
  test_microservices

  analyze_results "$RUN_DIR" "$WARMUP"

  echo ""
  info "============================================"
  info "  Experiment Complete!"
  info "============================================"
  info "  Run ID:   $TIMESTAMP"
  info "  Results:  $RUN_DIR/"
  info "  Charts:   $RUN_DIR/charts/"
  info "============================================"
}

main "$@"
