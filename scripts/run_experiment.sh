#!/usr/bin/env bash
# =============================================================================
# run_experiment.sh - Run the full benchmark experiment (local tooling)
# =============================================================================
# Builds Docker containers, benchmarks monolith then microservices
# sequentially, then runs analysis and generates charts.
#
# Requirements (host):
#   - docker / docker compose   (application containers only)
#   - jmeter (via sdkman or JMETER_HOME)
#   - python3 (or .venv/bin/python)
#
# Usage:
#   ./scripts/run_experiment.sh
#
# Options (env vars):
#   THREADS=50         Concurrent threads (default: 50)
#   DURATION=60        Test duration in seconds (default: 60)
#   WARMUP=15          Warmup duration in seconds (default: 15)
#   RAMP_UP=5          Ramp-up time in seconds (default: 5)
#   COOL_DOWN=15       Cool-down time between tests in seconds (default: 15)
# =============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

THREADS="${THREADS:-50}"
DURATION="${DURATION:-60}"
WARMUP="${WARMUP:-15}"
RAMP_UP="${RAMP_UP:-5}"
COOL_DOWN="${COOL_DOWN:-15}"

# Create timestamped run directory
RUN_DIR="$RESULTS_DIR/$TIMESTAMP"
mkdir -p "$RUN_DIR"

# ---------------------------------------------------------------------------
# Ensure setup is done (idempotent — fast if already set up)
# ---------------------------------------------------------------------------
info "Running setup (idempotent)..."
"$SCRIPT_DIR/setup.sh"

# ---------------------------------------------------------------------------
# Cleanup trap — tear down any running containers on unexpected exit
# ---------------------------------------------------------------------------
CURRENT_ARCH=""

cleanup_on_exit() {
  if [[ -n "$CURRENT_ARCH" ]]; then
    warn "Script interrupted. Cleaning up..."
    "$SCRIPT_DIR/cleanup.sh" "$CURRENT_ARCH"
  fi
}

trap cleanup_on_exit EXIT

# ---------------------------------------------------------------------------
# Pre-flight: check required tools
# ---------------------------------------------------------------------------
MISSING=()

if ! command -v docker &>/dev/null; then
  MISSING+=("docker")
fi

if ! detect_jmeter; then
  MISSING+=("jmeter")
fi

if ! detect_python; then
  MISSING+=("python3")
fi

if [[ ${#MISSING[@]} -gt 0 ]]; then
  error "Missing required tools: ${MISSING[*]}"
  info "Run ./scripts/setup.sh first, or install the missing tools."
  exit 1
fi

if ! docker info &>/dev/null; then
  error "Docker daemon is not running."
  exit 1
fi

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
echo "  JMeter:     ${JMETER:-N/A}"
echo "  Python:     $PYTHON"
echo "============================================"
echo ""

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

  "$JMETER" -n \
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
  "$JMETER" -g "$output_file" -o "$html_report_dir" || warn "HTML report generation failed (non-fatal)"
}

# ---------------------------------------------------------------------------
# Test monolith
# ---------------------------------------------------------------------------
test_monolith() {
  step "===== Testing MONOLITH architecture ====="

  CURRENT_ARCH="monolith"

  # Stop any previous runs
  docker compose -f "$PROJECT_DIR/docker-compose-monolith.yml" down -v 2>/dev/null || true

  # Build, start, and wait for healthchecks
  step "1/3 Building and starting monolith (waiting for healthchecks)..."
  docker compose -f "$PROJECT_DIR/docker-compose-monolith.yml" up --build --wait

  # Run benchmark
  step "2/3 Running benchmark..."
  run_jmeter "monolith" "localhost" "8080"

  # Stop
  step "3/3 Stopping monolith..."
  docker compose -f "$PROJECT_DIR/docker-compose-monolith.yml" down -v
  CURRENT_ARCH=""

  info "Monolith test complete."
}

# ---------------------------------------------------------------------------
# Test microservices
# ---------------------------------------------------------------------------
test_microservices() {
  step "===== Testing MICROSERVICES architecture ====="

  CURRENT_ARCH="microservices"

  # Stop any previous runs
  docker compose -f "$PROJECT_DIR/docker-compose-microservices.yml" down -v 2>/dev/null || true

  # Build, start, and wait for healthchecks
  step "1/3 Building and starting microservices (waiting for healthchecks)..."
  docker compose -f "$PROJECT_DIR/docker-compose-microservices.yml" up --build --wait

  # Run benchmark against gateway (port 8080 — same as monolith for fair comparison)
  step "2/3 Running benchmark..."
  run_jmeter "microservices" "localhost" "8080"

  # Stop
  step "3/3 Stopping microservices..."
  docker compose -f "$PROJECT_DIR/docker-compose-microservices.yml" down -v
  CURRENT_ARCH=""

  info "Microservices test complete."
}

# ---------------------------------------------------------------------------
# Run analysis
# ---------------------------------------------------------------------------
run_analysis() {
  step "Running analysis and generating charts..."

  local mono_file="$RUN_DIR/monolith.jtl"
  local micro_file="$RUN_DIR/microservices.jtl"

  if [[ ! -f "$mono_file" ]] || [[ ! -f "$micro_file" ]]; then
    warn "Cannot run comparison analysis — need both monolith and microservices results."
    if [[ -f "$mono_file" ]]; then
      info "Running single analysis for monolith..."
      "$PYTHON" "$PROJECT_DIR/python/visualize.py" \
        --single "$mono_file" \
        --label Monolith \
        --warmup "$WARMUP" \
        --output "$RUN_DIR/charts"
    elif [[ -f "$micro_file" ]]; then
      info "Running single analysis for microservices..."
      "$PYTHON" "$PROJECT_DIR/python/visualize.py" \
        --single "$micro_file" \
        --label Microservices \
        --warmup "$WARMUP" \
        --output "$RUN_DIR/charts"
    fi
    return 0
  fi

  info "Monolith results:       $mono_file"
  info "Microservices results:  $micro_file"

  "$PYTHON" "$PROJECT_DIR/python/visualize.py" \
    --monolith "$mono_file" \
    --microservices "$micro_file" \
    --warmup "$WARMUP" \
    --output "$RUN_DIR/charts" \
    --results-dir "$RUN_DIR"

  info "Charts saved to: $RUN_DIR/charts/"
}

# ---------------------------------------------------------------------------
# Main: run monolith, then microservices, then analysis
# ---------------------------------------------------------------------------
test_monolith
info "Cooling down for $COOL_DOWN seconds before next test..."
sleep "$COOL_DOWN"
test_microservices
run_analysis

echo ""
info "============================================"
info "  Experiment Complete!"
info "============================================"
info "  Run ID:   $TIMESTAMP"
info "  Results:  $RUN_DIR/"
info "  Charts:   $RUN_DIR/charts/"
info "============================================"
