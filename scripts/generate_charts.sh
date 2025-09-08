#!/bin/bash

# Go Chart Generator Wrapper
# Builds and runs the Go-based chart generator

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHARTGEN_DIR="$PROJECT_ROOT/cmd/chartgen"
BINARY_PATH="$PROJECT_ROOT/bin/chartgen"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS] [RESULTS_FILE]

Generate interactive HTML charts from NFS vs Direct Storage benchmark results using Go.

Options:
    -c, --chart TYPE      Chart type: throughput, latency, combined, dashboard, all (default: all)
    -o, --output DIR      Output directory for charts (default: same as input file)
    -h, --help           Show this help message

Arguments:
    RESULTS_FILE         Path to JSON results file (if not provided, finds latest)

Examples:
    $0                                    # Generate all charts for latest results
    $0 results.json                       # Generate all charts for specific file
    $0 -c throughput -o charts/           # Generate throughput chart only
    $0 -c dashboard                       # Generate dashboard only

Chart Types:
    throughput - Operations per second comparison
    latency    - Latency distribution (P50, P90, P95, P99)
    combined   - Side-by-side throughput and key latency metrics  
    dashboard  - Comprehensive view with all metrics
    all        - Generate all chart types (default)

Requirements:
    - Go 1.21+ (for building the chart generator)
    - Internet connection (for downloading dependencies on first run)
EOF
}

check_go() {
    if ! command -v go >/dev/null 2>&1; then
        print_error "Go is required but not installed."
        print_status "Install Go from: https://golang.org/doc/install"
        exit 1
    fi
    
    # Check Go version
    local go_version=$(go version | cut -d' ' -f3 | tr -d 'go')
    local required_version="1.21.0"
    
    if ! printf '%s\n%s\n' "$required_version" "$go_version" | sort -V -C; then
        print_warning "Go version $go_version found, but $required_version or higher is recommended."
    fi
}

build_chartgen() {
    print_status "Building chart generator..."
    
    # Ensure binary directory exists
    mkdir -p "$(dirname "$BINARY_PATH")"
    
    # Change to project root for go build
    cd "$PROJECT_ROOT"
    
    # Download dependencies and build
    go mod tidy
    go build -o "$BINARY_PATH" ./cmd/chartgen
    
    if [ $? -eq 0 ]; then
        print_success "Chart generator built successfully."
    else
        print_error "Failed to build chart generator."
        exit 1
    fi
}

ensure_chartgen() {
    # Check if binary exists and is newer than source
    if [ -f "$BINARY_PATH" ] && [ "$BINARY_PATH" -nt "$CHARTGEN_DIR/main.go" ]; then
        return 0
    fi
    
    build_chartgen
}

main() {
    local chart_type="all"
    local output_dir=""
    local results_file=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--chart)
                chart_type="$2"
                shift 2
                ;;
            -o|--output)
                output_dir="$2"
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            -*)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
            *)
                results_file="$1"
                shift
                ;;
        esac
    done
    
    # Check requirements
    check_go
    
    # Ensure chart generator is built
    ensure_chartgen
    
    # Prepare arguments for the Go binary
    local args=()
    
    if [ -n "$results_file" ]; then
        args+=("-input" "$results_file")
    fi
    
    if [ -n "$output_dir" ]; then
        args+=("-output" "$output_dir")
    fi
    
    args+=("-chart" "$chart_type")
    
    # Run the chart generator
    "$BINARY_PATH" "${args[@]}"
}

main "$@"
