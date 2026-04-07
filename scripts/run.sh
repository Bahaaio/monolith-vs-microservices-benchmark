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

trap cleanup EXIT

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
  uv sync --quiet

  info "Installing shared-lib into local Maven repository..."
  mvn -f "$PROJECT_DIR/shared-lib/pom.xml" install --quiet -DskipTests
}

print_header() {
  echo ""
  echo "============================================"
  echo "  Monolith vs Microservices Experiment"
  echo "============================================"
  echo "  Threads:    $THREADS"
  echo "  Duration:   ${DURATION}s"
  echo "  Warmup:     ${WARMUP}s"
  echo "  Ramp-up:    ${RAMP_UP}s"
  echo "  Cool-down:  ${COOL_DOWN}s"
  echo "  Run ID:     $TIMESTAMP"
  echo "  Output:     $RUN_DIR"
  echo "============================================"
  echo ""
}

# ---------------------------------------------------------------------------
# Helper: run JMeter
# ---------------------------------------------------------------------------
run_jmeter() {
  local arch="$1"
  local host="$2"
  local port="$3"
  local output_file="$RUN_DIR/${arch}.jtl"
  local log_file="$RUN_DIR/${arch}.log"

  info "Running JMeter for $arch -> $host:$port"
  info "  Threads=$THREADS, Duration=${DURATION}s, Warmup=${WARMUP}s"

  jmeter -n \
    -t "$PROJECT_DIR/jmeter/benchmark.jmx" \
    -l "$output_file" \
    -j "$log_file" \
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
  local html_report_dir="$RUN_DIR/${arch}_report"
  info "Generating JMeter HTML report -> $html_report_dir"
  jmeter -g "$output_file" -o "$html_report_dir" || warn "HTML report generation failed (non-fatal)"
}

# Analyze results and generate charts using the Python visualization script.
#
# Args:
#   run_dir:         Path to the timestamped run directory
#   warmup_seconds:  Number of warmup seconds to discard (default: 0)
#
# Expects:
#   $run_dir/monolith.jtl
#   $run_dir/microservices.jtl
#
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

  uv run python "$PROJECT_DIR/python/visualize.py" \
    --monolith "$mono_file" \
    --microservices "$micro_file" \
    --warmup "$warmup" \
    --output "$output_dir" \
    --results-dir "$run_dir"

  info "Charts saved to: $output_dir/"
}

# ---------------------------------------------------------------------------
# Test monolith
# ---------------------------------------------------------------------------
test_monolith() {
  step "===== Testing MONOLITH architecture ====="

  # Stop any previous runs
  docker compose -f "$PROJECT_DIR/docker-compose-monolith.yml" down -v 2>/dev/null || true

  step "1/3 Building and starting monolith (waiting for healthchecks)..."
  docker compose -f "$PROJECT_DIR/docker-compose-monolith.yml" up --build --wait

  step "2/3 Running benchmark..."
  run_jmeter "monolith" "localhost" "8080"

  step "3/3 Stopping monolith..."
  docker compose -f "$PROJECT_DIR/docker-compose-monolith.yml" down -v

  info "Monolith test complete."
}

# ---------------------------------------------------------------------------
# Test microservices
# ---------------------------------------------------------------------------
test_microservices() {
  step "===== Testing MICROSERVICES architecture ====="

  # Stop any previous runs
  docker compose -f "$PROJECT_DIR/docker-compose-microservices.yml" down -v 2>/dev/null || true

  step "1/3 Building and starting microservices (waiting for healthchecks)..."
  docker compose -f "$PROJECT_DIR/docker-compose-microservices.yml" up --build --wait

  step "2/3 Running benchmark..."
  run_jmeter "microservices" "localhost" "8080"

  step "3/3 Stopping microservices..."
  docker compose -f "$PROJECT_DIR/docker-compose-microservices.yml" down -v

  info "Microservices test complete."
}

main() {
  check_dependencies
  setup
  print_header

  test_monolith

  info "Cooling down for $COOL_DOWN seconds..."
  sleep "$COOL_DOWN"

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
