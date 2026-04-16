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
#   SCENARIOS=baseline,fault_injection,latency_injection,pool_exhaustion
#                      Comma-separated scenarios to execute in order
#   FAULT_IDS=3,7,11   Deterministic failing product IDs for fault_injection
#   LATENCY_MS=100     Fixed delay in ms for latency_injection
#   POOL_MAX_SIZES=2,5,10  Hikari max pool sizes for pool_exhaustion sweep
#   POOL_TIMEOUT_MS=2000  Hikari connection timeout for pool_exhaustion
#   POOL_RUNS=2        Number of runs per pool size (pool_exhaustion only)
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
SCENARIOS="${SCENARIOS:-baseline,fault_injection,latency_injection,pool_exhaustion}"

FAULT_IDS="${FAULT_IDS:-3,7,11}"
LATENCY_MS="${LATENCY_MS:-100}"
POOL_MAX_SIZES="${POOL_MAX_SIZES:-2,5,10}"
POOL_TIMEOUT_MS="${POOL_TIMEOUT_MS:-2000}"
POOL_RUNS="${POOL_RUNS:-2}"

SCENARIO_THREADS="$THREADS"
SCENARIO_CHAOS_ENABLED="false"
SCENARIO_CHAOS_MODE="none"
SCENARIO_CHAOS_FAULT_IDS=""
SCENARIO_CHAOS_LATENCY_MS="0"
SCENARIO_POOL_MAX_SIZE="10"
SCENARIO_POOL_TIMEOUT_MS="2000"
SCENARIO_POOL_MIN_IDLE="2"

IFS=',' read -r -a SCENARIO_LIST <<<"$SCENARIOS"
IFS=',' read -r -a POOL_MAX_SIZE_LIST <<<"$POOL_MAX_SIZES"

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

  info "Building monolith image once..."
  # docker compose -f "$PROJECT_DIR/docker-compose-monolith.yml" build --quiet

  info "Building microservices images once..."
  # docker compose -f "$PROJECT_DIR/docker-compose-microservices.yml" build --quiet
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
  info "  Scenarios:  ${SCENARIOS}"
  info "  Fault IDs:  ${FAULT_IDS}"
  info "  Pool sizes: ${POOL_MAX_SIZES}"
  info "  Pool runs:  ${POOL_RUNS}"
  info "  Run ID:     $TIMESTAMP"
  info "  Output:     $RUN_DIR"
  info "============================================"
  echo ""
}

configure_scenario() {
  local scenario="$1"
  local pool_size="${2:-}"

  SCENARIO_THREADS="$THREADS"
  SCENARIO_CHAOS_ENABLED="false"
  SCENARIO_CHAOS_MODE="none"
  SCENARIO_CHAOS_FAULT_IDS=""
  SCENARIO_CHAOS_LATENCY_MS="0"
  SCENARIO_POOL_MAX_SIZE="10"
  SCENARIO_POOL_TIMEOUT_MS="2000"
  SCENARIO_POOL_MIN_IDLE="2"

  case "$scenario" in
  baseline) ;;
  fault_injection)
    SCENARIO_CHAOS_ENABLED="true"
    SCENARIO_CHAOS_MODE="fault"
    SCENARIO_CHAOS_FAULT_IDS="$FAULT_IDS"
    ;;
  latency_injection)
    SCENARIO_CHAOS_ENABLED="true"
    SCENARIO_CHAOS_MODE="latency"
    SCENARIO_CHAOS_LATENCY_MS="$LATENCY_MS"
    ;;
  pool_exhaustion)
    if [[ -z "$pool_size" ]]; then
      error "pool_exhaustion requires a pool size"
      exit 1
    fi
    SCENARIO_POOL_MAX_SIZE="$pool_size"
    SCENARIO_POOL_TIMEOUT_MS="$POOL_TIMEOUT_MS"
    if [[ "$pool_size" -le 2 ]]; then
      SCENARIO_POOL_MIN_IDLE="$pool_size"
    else
      SCENARIO_POOL_MIN_IDLE="2"
    fi
    ;;
  *)
    error "Unknown scenario: $scenario"
    exit 1
    ;;
  esac
}

print_scenario_config() {
  local scenario="$1"
  info "Scenario: $scenario"
  info "  Threads:            $SCENARIO_THREADS"
  info "  Chaos enabled:      $SCENARIO_CHAOS_ENABLED"
  if [[ "$SCENARIO_CHAOS_ENABLED" == "true" ]]; then
    info "  Chaos mode:         $SCENARIO_CHAOS_MODE"
    info "  Chaos fault IDs:    $SCENARIO_CHAOS_FAULT_IDS"
    info "  Chaos latency ms:   $SCENARIO_CHAOS_LATENCY_MS"
  fi
  info "  Pool max size:      $SCENARIO_POOL_MAX_SIZE"
  info "  Pool min idle:      $SCENARIO_POOL_MIN_IDLE"
  info "  Pool timeout ms:    $SCENARIO_POOL_TIMEOUT_MS"
}

write_scenario_metadata() {
  local scenario_dir="$1"
  local scenario="$2"

  cat >"$scenario_dir/scenario_config.csv" <<EOF
scenario,threads,chaos_enabled,chaos_mode,chaos_fault_ids,chaos_latency_ms,pool_max_size,pool_min_idle,pool_timeout_ms
$scenario,$SCENARIO_THREADS,$SCENARIO_CHAOS_ENABLED,$SCENARIO_CHAOS_MODE,"$SCENARIO_CHAOS_FAULT_IDS",$SCENARIO_CHAOS_LATENCY_MS,$SCENARIO_POOL_MAX_SIZE,$SCENARIO_POOL_MIN_IDLE,$SCENARIO_POOL_TIMEOUT_MS
EOF
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
  local threads="$6"

  info "Running JMeter for $arch -> $host:$port"

  jmeter -n \
    -t "$PROJECT_DIR/jmeter/benchmark.jmx" \
    -l "$output_file" \
    -Jhost="$host" \
    -Jport="$port" \
    -Jusers_port="$port" \
    -Jproducts_port="$port" \
    -Jorders_port="$port" \
    -Jthreads="$threads" \
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
compose_up_with_scenario_env() {
  local compose_file="$1"

  CHAOS_ENABLED="$SCENARIO_CHAOS_ENABLED" \
    CHAOS_MODE="$SCENARIO_CHAOS_MODE" \
    CHAOS_FAULT_IDS="$SCENARIO_CHAOS_FAULT_IDS" \
    CHAOS_LATENCY_MS="$SCENARIO_CHAOS_LATENCY_MS" \
    SPRING_DATASOURCE_HIKARI_MAXIMUM_POOL_SIZE="$SCENARIO_POOL_MAX_SIZE" \
    SPRING_DATASOURCE_HIKARI_MINIMUM_IDLE="$SCENARIO_POOL_MIN_IDLE" \
    SPRING_DATASOURCE_HIKARI_CONNECTION_TIMEOUT="$SCENARIO_POOL_TIMEOUT_MS" \
    docker compose -f "$compose_file" up --wait
}

test_architecture() {
  local scenario="$1"
  local scenario_dir="$2"
  local scenario_runs="$3"
  local arch="$4"
  local compose_file="$PROJECT_DIR/docker-compose-$arch.yml"
  local arch_dir="$scenario_dir/$arch"
  local arch_name

  if [[ "$arch" == "monolith" ]]; then
    arch_name="Monolith"
  else
    arch_name="Microservices"
  fi

  mkdir -p "$arch_dir"

  step "===== [$scenario] Testing ${arch_name^^} architecture ($scenario_runs runs) ====="

  for run in $(seq 1 "$scenario_runs"); do
    local output_file="$arch_dir/run_${run}.jtl"
    local html_report_dir="$arch_dir/run_${run}_report"

    step "[$scenario][$arch_name] Run $run/$scenario_runs - cleaning environment..."
    docker compose -f "$compose_file" down -v --remove-orphans 2>/dev/null || true

    step "[$scenario][$arch_name] Run $run/$scenario_runs - starting stack..."
    compose_up_with_scenario_env "$compose_file"

    step "[$scenario][$arch_name] Run $run/$scenario_runs - benchmarking..."
    run_jmeter "$arch" "localhost" "8080" "$output_file" "$html_report_dir" "$SCENARIO_THREADS"

    step "[$scenario][$arch_name] Run $run/$scenario_runs - stopping stack..."
    docker compose -f "$compose_file" down -v --remove-orphans

    if [[ "$run" -lt "$scenario_runs" ]]; then
      info "Cooling down for $COOL_DOWN seconds before next $arch_name run..."
      sleep "$COOL_DOWN"
    fi
  done

  info "[$scenario] $arch_name runs complete."
}

test_monolith() {
  test_architecture "$1" "$2" "$3" "monolith"
}

# ---------------------------------------------------------------------------
# Test microservices
# ---------------------------------------------------------------------------
test_microservices() {
  test_architecture "$1" "$2" "$3" "microservices"
}

main() {
  check_dependencies
  setup
  print_header

  for scenario in "${SCENARIO_LIST[@]}"; do
    local_scenario="$(echo "$scenario" | xargs)"

    if [[ "$local_scenario" == "pool_exhaustion" ]]; then
      for pool_size in "${POOL_MAX_SIZE_LIST[@]}"; do
        local trimmed_pool_size
        trimmed_pool_size="$(echo "$pool_size" | xargs)"
        if [[ -z "$trimmed_pool_size" ]]; then
          continue
        fi

        local pool_scenario_name="pool_exhaustion_p${trimmed_pool_size}"
        configure_scenario "pool_exhaustion" "$trimmed_pool_size"
        print_scenario_config "$pool_scenario_name"

        local scenario_dir="$RUN_DIR/$pool_scenario_name"
        mkdir -p "$scenario_dir"
        write_scenario_metadata "$scenario_dir" "$pool_scenario_name"

        test_monolith "$pool_scenario_name" "$scenario_dir" "$POOL_RUNS"
        test_microservices "$pool_scenario_name" "$scenario_dir" "$POOL_RUNS"

        analyze_results "$scenario_dir" "$WARMUP"
      done
    else
      configure_scenario "$local_scenario"
      print_scenario_config "$local_scenario"

      local scenario_dir="$RUN_DIR/$local_scenario"
      mkdir -p "$scenario_dir"
      write_scenario_metadata "$scenario_dir" "$local_scenario"

      test_monolith "$local_scenario" "$scenario_dir" "$RUNS"
      test_microservices "$local_scenario" "$scenario_dir" "$RUNS"

      analyze_results "$scenario_dir" "$WARMUP"
    fi
  done

  echo ""
  info "============================================"
  info "  Experiment Complete!"
  info "============================================"
  info "  Run ID:   $TIMESTAMP"
  info "  Results:  $RUN_DIR/"
  info "  Charts:   $RUN_DIR/<scenario>/charts/"
  info "============================================"
}

main "$@"
