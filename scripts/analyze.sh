#!/usr/bin/env bash
# =============================================================================
# analyze.sh - Run Python visualization on benchmark results
# =============================================================================
# Usage:
#   ./scripts/analyze.sh                                    # Auto-detect latest run
#   ./scripts/analyze.sh results/2026-03-08_14-30-00        # Specific run directory
#   ./scripts/analyze.sh results/mono.jtl results/micro.jtl # Specific files
#   ./scripts/analyze.sh --single results/mono.jtl          # Single analysis
# =============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

if ! detect_python; then
    error "Python not found. Run ./scripts/setup.sh first."
    exit 1
fi

# Install Python dependencies if needed
if ! "$PYTHON" -c "import pandas, matplotlib, seaborn" 2>/dev/null; then
    info "Installing Python dependencies..."
    "$PYTHON" -m pip install -r "$PROJECT_DIR/python/requirements.txt" --quiet
fi

if [[ "${1:-}" == "--single" ]]; then
    SINGLE_FILE="${2:-}"
    LABEL="${3:-Benchmark}"
    OUTPUT_DIR="${4:-$RESULTS_DIR/charts}"
    if [[ -z "$SINGLE_FILE" ]]; then
        error "Usage: $0 --single <file.jtl> [label] [output_dir]"
        exit 1
    fi
    info "Running single analysis on: $SINGLE_FILE"
    "$PYTHON" "$PROJECT_DIR/python/visualize.py" \
        --single "$SINGLE_FILE" \
        --label "$LABEL" \
        --output "$OUTPUT_DIR"
elif [[ $# -eq 2 && -f "$1" && -f "$2" ]]; then
    # Two .jtl files provided
    MONO_FILE="$1"
    MICRO_FILE="$2"
    OUTPUT_DIR="$RESULTS_DIR/charts"
    RUN_DIR_FOR_SCALING="$(dirname "$MONO_FILE")"
    
    info "Running comparison analysis..."
    "$PYTHON" "$PROJECT_DIR/python/visualize.py" \
        --monolith "$MONO_FILE" \
        --microservices "$MICRO_FILE" \
        --output "$OUTPUT_DIR" \
        --results-dir "$RUN_DIR_FOR_SCALING"
    info "Analysis complete. Charts saved to: $OUTPUT_DIR"
elif [[ $# -eq 1 && -d "$1" ]]; then
    # Run directory provided
    RUN_DIR="$1"
    MONO_FILE="$RUN_DIR/monolith.jtl"
    MICRO_FILE="$RUN_DIR/microservices.jtl"
    OUTPUT_DIR="$RUN_DIR/charts"
    
    if [[ ! -f "$MONO_FILE" ]] || [[ ! -f "$MICRO_FILE" ]]; then
        error "Run directory missing required files: monolith.jtl and/or microservices.jtl"
        exit 1
    fi
    
    info "Analyzing run: $RUN_DIR"
    info "  Monolith:       $MONO_FILE"
    info "  Microservices:  $MICRO_FILE"
    
    "$PYTHON" "$PROJECT_DIR/python/visualize.py" \
        --monolith "$MONO_FILE" \
        --microservices "$MICRO_FILE" \
        --output "$OUTPUT_DIR" \
        --results-dir "$RUN_DIR"
    info "Analysis complete. Charts saved to: $OUTPUT_DIR"
else
    # Auto-detect latest run directory
    LATEST_RUN=$(find "$RESULTS_DIR" -maxdepth 1 -type d -name "20*" 2>/dev/null | sort -r | head -1)
    
    if [[ -z "$LATEST_RUN" ]]; then
        error "No run directories found in $RESULTS_DIR"
        info ""
        info "Usage:"
        info "  $0                                         # Auto-detect latest run"
        info "  $0 results/2026-03-08_14-30-00             # Specific run directory"
        info "  $0 <monolith.jtl> <microservices.jtl>      # Specific files"
        info "  $0 --single <file.jtl> [label] [out_dir]   # Single analysis"
        exit 1
    fi
    
    MONO_FILE="$LATEST_RUN/monolith.jtl"
    MICRO_FILE="$LATEST_RUN/microservices.jtl"
    OUTPUT_DIR="$LATEST_RUN/charts"

    if [[ ! -f "$MONO_FILE" ]] || [[ ! -f "$MICRO_FILE" ]]; then
        error "Latest run directory missing required files: monolith.jtl and/or microservices.jtl"
        info "Run directory: $LATEST_RUN"
        exit 1
    fi

    info "Auto-detected latest run: $(basename "$LATEST_RUN")"
    info "  Monolith:       $MONO_FILE"
    info "  Microservices:  $MICRO_FILE"

    "$PYTHON" "$PROJECT_DIR/python/visualize.py" \
        --monolith "$MONO_FILE" \
        --microservices "$MICRO_FILE" \
        --output "$OUTPUT_DIR" \
        --results-dir "$LATEST_RUN"
    info "Analysis complete. Charts saved to: $OUTPUT_DIR"
fi
