#!/bin/bash

# Visualization Demo Script
# This script demonstrates the visualization capabilities without requiring real benchmark data

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
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

create_sample_results() {
    local results_dir="$1"
    local results_file="$2"
    
    mkdir -p "$results_dir"
    
    # Create sample benchmark results JSON
    cat > "$results_file" << 'EOF'
{
  "metadata": {
    "timestamp": "2025-01-15T10:30:00Z",
    "database_type": "postgresql",
    "scenario": "heavy_inserts",
    "version": "1.0.0"
  },
  "direct": {
    "Duration": 180000000000,
    "Metrics": {
      "total_operations": 50000,
      "operations_per_second": 277.8,
      "average_latency": 18000000,
      "min_latency": 5000000,
      "max_latency": 150000000,
      "p50_latency": 15000000,
      "p90_latency": 35000000,
      "p95_latency": 45000000,
      "p99_latency": 80000000
    },
    "DBStats": {
      "final_record_count": 50000,
      "table_size_bytes": 15728640,
      "index_size_bytes": 2097152
    }
  },
  "nfs": {
    "Duration": 240000000000,
    "Metrics": {
      "total_operations": 37500,
      "operations_per_second": 156.3,
      "average_latency": 32000000,
      "min_latency": 8000000,
      "max_latency": 300000000,
      "p50_latency": 28000000,
      "p90_latency": 75000000,
      "p95_latency": 120000000,
      "p99_latency": 250000000
    },
    "DBStats": {
      "final_record_count": 37500,
      "table_size_bytes": 11796480,
      "index_size_bytes": 1572864
    }
  }
}
EOF

    print_success "Sample results created: $results_file"
}

demo_table_view() {
    local results_file="$1"
    
    echo -e "${BOLD}=== Demo: Table View ===${NC}"
    echo ""
    
    print_status "Displaying results in formatted table..."
    "$SCRIPT_DIR/view_results.sh" "$results_file"
    echo ""
}

demo_csv_export() {
    local results_file="$1"
    local output_dir="$2"
    
    echo -e "${BOLD}=== Demo: CSV Export ===${NC}"
    echo ""
    
    local csv_file="$output_dir/demo_results.csv"
    
    print_status "Exporting results to CSV format..."
    "$SCRIPT_DIR/view_results.sh" -f csv -o "$csv_file" "$results_file"
    
    print_status "CSV file contents:"
    head -5 "$csv_file"
    echo ""
}

demo_html_report() {
    local results_file="$1"
    local output_dir="$2"
    
    echo -e "${BOLD}=== Demo: HTML Report ===${NC}"
    echo ""
    
    local html_file="$output_dir/demo_report.html"
    
    print_status "Generating HTML report with charts..."
    "$SCRIPT_DIR/view_results.sh" -f html -c -o "$html_file" "$results_file"
    
    print_status "HTML report file size: $(ls -lh "$html_file" | awk '{print $5}')"
    print_status "To view the report, open: file://$html_file"
    echo ""
}

demo_go_charts() {
    local results_file="$1"
    local output_dir="$2"
    
    echo -e "${BOLD}=== Demo: Go Charts ===${NC}"
    echo ""
    
    # Check if Go is available
    if ! command -v go >/dev/null 2>&1; then
        print_warning "Go not available. To install:"
        echo "    Visit: https://golang.org/doc/install"
        echo ""
        print_status "Chart generation demo skipped."
        return 0
    fi
    
    print_status "Generating interactive HTML charts..."
    "$SCRIPT_DIR/generate_charts.sh" -c all -o "$output_dir/charts" "$results_file"
    
    if [ -d "$output_dir/charts" ]; then
        print_status "Generated chart files:"
        ls -la "$output_dir/charts/"
        print_status "Open any .html file in your web browser to view interactive charts."
    fi
    echo ""
}

demo_comparison_only() {
    local results_file="$1"
    
    echo -e "${BOLD}=== Demo: Comparison Only ===${NC}"
    echo ""
    
    print_status "Showing only performance comparison metrics..."
    "$SCRIPT_DIR/view_results.sh" -C "$results_file"
    echo ""
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Demonstrate the visualization capabilities of the NFS benchmark suite.

Options:
    --clean         Remove demo files after completion
    --output-dir    Directory for demo outputs (default: /tmp/nfs_demo)
    --help          Show this help message

This script will:
1. Create sample benchmark results
2. Demonstrate table view
3. Export to CSV
4. Generate HTML report with charts
5. Generate Go-based interactive charts (if Go available)
6. Show comparison-only view

EOF
}

main() {
    local clean_after=false
    local output_dir="/tmp/nfs_demo"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --clean)
                clean_after=true
                shift
                ;;
            --output-dir)
                output_dir="$2"
                shift 2
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    echo -e "${BOLD}🎨 NFS Benchmark Visualization Demo${NC}"
    echo -e "${BOLD}===================================${NC}"
    echo ""
    
    # Setup
    local results_dir="$output_dir/results/run_20250115_103000"
    local results_file="$results_dir/postgresql_heavy_inserts.json"
    
    print_status "Setting up demo environment in: $output_dir"
    create_sample_results "$results_dir" "$results_file"
    echo ""
    
    # Run demos
    demo_table_view "$results_file"
    demo_comparison_only "$results_file"
    demo_csv_export "$results_file" "$output_dir"
    demo_html_report "$results_file" "$output_dir"
    demo_go_charts "$results_file" "$output_dir"
    
    # Summary
    echo -e "${BOLD}=== Demo Summary ===${NC}"
    print_success "All visualization demos completed!"
    echo ""
    print_status "Generated files:"
    find "$output_dir" -type f | sort
    echo ""
    
    if [ "$clean_after" = true ]; then
        print_status "Cleaning up demo files..."
        rm -rf "$output_dir"
        print_success "Demo files cleaned up."
    else
        print_status "Demo files kept in: $output_dir"
        print_status "Use --clean flag to remove them automatically."
    fi
    
    echo ""
    print_success "Demo completed! 🎉"
}

main "$@"
