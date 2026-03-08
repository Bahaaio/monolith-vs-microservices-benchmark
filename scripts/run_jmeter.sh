#!/usr/bin/env bash
# =============================================================================
# run_jmeter.sh - Run JMeter benchmark test
# =============================================================================
# Usage:
#   ./scripts/run_jmeter.sh monolith      # Test monolith (localhost:8080)
#   ./scripts/run_jmeter.sh microservices  # Test microservices via gateway (localhost:8080)
#
# Options (env vars):
#   THREADS=100        Number of concurrent threads (default: 50)
#   DURATION=60        Test duration in seconds (default: 60)
#   WARMUP=15          Warmup duration in seconds (default: 15)
#   RAMP_UP=5          Ramp-up time in seconds (default: 5)
#   JMETER_HOME=...    Path to JMeter (default: auto-detect)
# =============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

ARCH="${1:-}"
THREADS="${THREADS:-50}"
DURATION="${DURATION:-60}"
WARMUP="${WARMUP:-15}"
RAMP_UP="${RAMP_UP:-5}"
HOST="${HOST:-localhost}"

if [[ -z "$ARCH" ]]; then
  echo "Usage: $0 <monolith|microservices>"
  echo ""
  echo "Environment variables:"
  echo "  THREADS=50       Concurrent threads"
  echo "  DURATION=60      Test duration (seconds)"
  echo "  WARMUP=15        Warmup duration (seconds)"
  echo "  RAMP_UP=5        Ramp-up time (seconds)"
  echo "  HOST=localhost    Target host"
  exit 1
fi

if ! detect_jmeter; then
  error "JMeter not found. Install JMeter or set JMETER_HOME."
  exit 1
fi

OUTPUT_FILE="$RESULTS_DIR/${ARCH}_${TIMESTAMP}.jtl"
LOG_FILE="$RESULTS_DIR/${ARCH}_${TIMESTAMP}.log"

JMX_FILE="$PROJECT_DIR/jmeter/benchmark.jmx"

case "$ARCH" in
monolith)
  PORT=8080
  USERS_PORT=8080
  PRODUCTS_PORT=8080
  ORDERS_PORT=8080
  ;;
microservices)
  # Route through API Gateway on port 8080 (same as monolith for fair comparison)
  PORT=8080
  USERS_PORT=8080
  PRODUCTS_PORT=8080
  ORDERS_PORT=8080
  ;;
*)
  error "Unknown architecture: $ARCH"
  exit 1
  ;;
esac

info "============================================"
info "  Benchmark Configuration"
info "============================================"
info "  Architecture:  $ARCH"
info "  Host:          $HOST"
info "  Port:          $PORT"
info "  Threads:       $THREADS"
info "  Duration:      ${DURATION}s"
info "  Warmup:        ${WARMUP}s"
info "  Ramp-up:       ${RAMP_UP}s"
info "  Output:        $OUTPUT_FILE"
info "============================================"

info "Starting JMeter benchmark..."

"$JMETER" -n \
  -t "$JMX_FILE" \
  -l "$OUTPUT_FILE" \
  -j "$LOG_FILE" \
  -Jhost="$HOST" \
  -Jport="$PORT" \
  -Jusers_port="$USERS_PORT" \
  -Jproducts_port="$PRODUCTS_PORT" \
  -Jorders_port="$ORDERS_PORT" \
  -Jthreads="$THREADS" \
  -Jduration="$DURATION" \
  -Jwarmup="$WARMUP" \
  -Jrampup="$RAMP_UP" \
  -Joutput="$OUTPUT_FILE"

info "Benchmark complete!"
info "Results:  $OUTPUT_FILE"
info "Log:      $LOG_FILE"

# Quick summary
if [[ -f "$OUTPUT_FILE" ]]; then
  TOTAL_LINES=$(wc -l <"$OUTPUT_FILE")
  TOTAL_REQUESTS=$((TOTAL_LINES - 1)) # Subtract header
  ERROR_COUNT=$(awk -F',' 'NR>1 && $8=="false"{count++} END{print count+0}' "$OUTPUT_FILE")
  info "Total requests: $TOTAL_REQUESTS"
  info "Errors: $ERROR_COUNT"
fi
