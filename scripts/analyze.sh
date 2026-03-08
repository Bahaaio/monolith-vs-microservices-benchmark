#!/usr/bin/env bash
# =============================================================================
# analyze.sh - Run Python visualization on benchmark results
# =============================================================================
# Usage:
#   ./scripts/analyze.sh                                    # Auto-detect latest results
#   ./scripts/analyze.sh results/mono.jtl results/micro.jtl # Specific files
#   ./scripts/analyze.sh --single results/mono.jtl          # Single analysis
# =============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

if ! detect_python; then
    error "Python not found. Run ./scripts/setup.sh first."
    exit 1
fi

OUTPUT_DIR="$RESULTS_DIR/charts"

# Install Python dependencies if needed
if ! "$PYTHON" -c "import pandas, matplotlib, seaborn" 2>/dev/null; then
    info "Installing Python dependencies..."
    "$PYTHON" -m pip install -r "$PROJECT_DIR/python/requirements.txt" --quiet
fi

if [[ "${1:-}" == "--single" ]]; then
    SINGLE_FILE="${2:-}"
    LABEL="${3:-Benchmark}"
    if [[ -z "$SINGLE_FILE" ]]; then
        error "Usage: $0 --single <file.jtl> [label]"
        exit 1
    fi
    info "Running single analysis on: $SINGLE_FILE"
    "$PYTHON" "$PROJECT_DIR/python/visualize.py" \
        --single "$SINGLE_FILE" \
        --label "$LABEL" \
        --output "$OUTPUT_DIR"
elif [[ $# -eq 2 ]]; then
    MONO_FILE="$1"
    MICRO_FILE="$2"
    info "Running comparison analysis..."
    "$PYTHON" "$PROJECT_DIR/python/visualize.py" \
        --monolith "$MONO_FILE" \
        --microservices "$MICRO_FILE" \
        --output "$OUTPUT_DIR" \
        --results-dir "$RESULTS_DIR"
else
    # Auto-detect latest results
    MONO_FILE=$(ls -t "$RESULTS_DIR"/monolith_*.jtl 2>/dev/null | head -1)
    MICRO_FILE=$(ls -t "$RESULTS_DIR"/microservices_*.jtl 2>/dev/null | head -1)

    if [[ -z "$MONO_FILE" ]] || [[ -z "$MICRO_FILE" ]]; then
        error "Could not auto-detect result files."
        info "Expected files in $RESULTS_DIR: monolith_*.jtl, microservices_*.jtl"
        info ""
        info "Usage:"
        info "  $0                                    # Auto-detect"
        info "  $0 <monolith.jtl> <microservices.jtl> # Specify files"
        info "  $0 --single <file.jtl> [label]        # Single analysis"
        exit 1
    fi

    info "Auto-detected results:"
    info "  Monolith:       $MONO_FILE"
    info "  Microservices:  $MICRO_FILE"

    "$PYTHON" "$PROJECT_DIR/python/visualize.py" \
        --monolith "$MONO_FILE" \
        --microservices "$MICRO_FILE" \
        --output "$OUTPUT_DIR" \
        --results-dir "$RESULTS_DIR"
fi

info "Analysis complete. Charts saved to: $OUTPUT_DIR"
