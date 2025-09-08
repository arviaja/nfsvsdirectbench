#!/bin/bash

# Results Viewer - Display benchmark results in table format
# Supports both console tables and HTML output with charts

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Default values
RESULTS_FILE=""
FORMAT="table"
OUTPUT_FILE=""
SHOW_CHARTS=false
COMPARISON_ONLY=false

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS] [RESULTS_FILE]

Display benchmark results in various formats with optional charts.

Options:
    -f, --format FORMAT     Output format: table, csv, html, json (default: table)
    -o, --output FILE       Save output to file instead of stdout
    -c, --charts            Generate charts (requires format=html)
    -C, --comparison-only   Show only comparison metrics (overhead %)
    -h, --help             Show this help message

Arguments:
    RESULTS_FILE           Path to JSON results file (if not provided, finds latest)

Examples:
    $0                                    # Show latest results in table format
    $0 results/run_20250101_120000/postgresql_heavy_inserts.json
    $0 -f html -c -o report.html         # Generate HTML report with charts
    $0 -f csv -o results.csv             # Export to CSV
    $0 -C                                # Show only performance comparison

Supported formats:
    table    - Console table with colors and formatting
    csv      - Comma-separated values for spreadsheet import
    html     - HTML page with styling and optional charts
    json     - Pretty-formatted JSON output
EOF
}

find_latest_results() {
    local results_dir="./results"
    if [ ! -d "$results_dir" ]; then
        print_error "No results directory found. Run a benchmark first."
        exit 1
    fi
    
    local latest_file
    latest_file=$(find "$results_dir" -name "*.json" -type f | sort -r | head -1)
    
    if [ -z "$latest_file" ]; then
        print_error "No JSON results files found in $results_dir"
        exit 1
    fi
    
    echo "$latest_file"
}

# Function to display results in table format
show_table_format() {
    local file="$1"
    
    if ! command -v jq >/dev/null 2>&1; then
        print_error "jq is required for table format. Install with: brew install jq"
        return 1
    fi
    
    echo -e "${BOLD}📊 NFS vs Direct Storage Benchmark Results${NC}"
    echo -e "${BOLD}=============================================${NC}"
    echo ""
    
    # Extract metadata
    local direct_ops direct_latency direct_p95 direct_duration
    local nfs_ops nfs_latency nfs_p95 nfs_duration
    local direct_records nfs_records direct_size_mb nfs_size_mb
    
    # Get metrics (convert nanoseconds to milliseconds for latency)
    direct_ops=$(jq -r '.direct.Metrics.operations_per_second' "$file" 2>/dev/null | xargs printf "%.1f")
    direct_latency=$(jq -r '.direct.Metrics.average_latency / 1000000' "$file" 2>/dev/null | xargs printf "%.1f")
    direct_p95=$(jq -r '.direct.Metrics.p95_latency / 1000000' "$file" 2>/dev/null | xargs printf "%.1f")
    direct_duration=$(jq -r '.direct.Duration / 1000000000' "$file" 2>/dev/null | xargs printf "%.1f")
    direct_records=$(jq -r '.direct.DBStats.final_record_count' "$file" 2>/dev/null)
    direct_size_mb=$(jq -r '.direct.DBStats.table_size_bytes / 1024 / 1024' "$file" 2>/dev/null | xargs printf "%.0f")
    
    nfs_ops=$(jq -r '.nfs.Metrics.operations_per_second' "$file" 2>/dev/null | xargs printf "%.1f")
    nfs_latency=$(jq -r '.nfs.Metrics.average_latency / 1000000' "$file" 2>/dev/null | xargs printf "%.1f")
    nfs_p95=$(jq -r '.nfs.Metrics.p95_latency / 1000000' "$file" 2>/dev/null | xargs printf "%.1f")
    nfs_duration=$(jq -r '.nfs.Duration / 1000000000' "$file" 2>/dev/null | xargs printf "%.1f")
    nfs_records=$(jq -r '.nfs.DBStats.final_record_count' "$file" 2>/dev/null)
    nfs_size_mb=$(jq -r '.nfs.DBStats.table_size_bytes / 1024 / 1024' "$file" 2>/dev/null | xargs printf "%.0f")
    
    # Performance comparison table
    echo -e "${CYAN}Performance Comparison${NC}"
    printf "╔══════════════════════╦═══════════════╦═══════════════╦═══════════════╦═══════════════╗\n"
    printf "║ %-20s ║ %-13s ║ %-13s ║ %-13s ║ %-13s ║\n" "Storage Type" "Throughput" "Avg Latency" "P95 Latency" "Duration"
    printf "╠══════════════════════╬═══════════════╬═══════════════╬═══════════════╬═══════════════╣\n"
    printf "║ %-20s ║ %8s ops/s ║ %10s ms ║ %10s ms ║ %10s s ║\n" "Direct Storage" "$direct_ops" "$direct_latency" "$direct_p95" "$direct_duration"
    printf "║ %-20s ║ %8s ops/s ║ %10s ms ║ %10s ms ║ %10s s ║\n" "NFS Storage" "$nfs_ops" "$nfs_latency" "$nfs_p95" "$nfs_duration"
    printf "╚══════════════════════╩═══════════════╩═══════════════╩═══════════════╩═══════════════╝\n"
    echo ""
    
    # Calculate performance overhead using raw values from JSON
    if command -v bc >/dev/null 2>&1; then
        local raw_direct_ops raw_nfs_ops raw_direct_latency raw_nfs_latency raw_direct_p95 raw_nfs_p95
        local throughput_overhead latency_overhead p95_overhead
        
        # Get raw values for precise calculations
        raw_direct_ops=$(jq -r '.direct.Metrics.operations_per_second' "$file" 2>/dev/null)
        raw_nfs_ops=$(jq -r '.nfs.Metrics.operations_per_second' "$file" 2>/dev/null)
        raw_direct_latency=$(jq -r '.direct.Metrics.average_latency' "$file" 2>/dev/null)
        raw_nfs_latency=$(jq -r '.nfs.Metrics.average_latency' "$file" 2>/dev/null)
        raw_direct_p95=$(jq -r '.direct.Metrics.p95_latency' "$file" 2>/dev/null)
        raw_nfs_p95=$(jq -r '.nfs.Metrics.p95_latency' "$file" 2>/dev/null)
        
        throughput_overhead=$(echo "scale=5; (($raw_direct_ops - $raw_nfs_ops) / $raw_direct_ops) * 100" | bc -l | xargs printf "%.2f")
        latency_overhead=$(echo "scale=5; (($raw_nfs_latency - $raw_direct_latency) / $raw_direct_latency) * 100" | bc -l | xargs printf "%.2f")
        p95_overhead=$(echo "scale=5; (($raw_nfs_p95 - $raw_direct_p95) / $raw_direct_p95) * 100" | bc -l | xargs printf "%.2f")
        
        echo -e "${YELLOW}Performance Impact (NFS vs Direct)${NC}"
        printf "╔═══════════════════════════════╦═══════════════════════════════╗\n"
        printf "║ %-29s ║ %-29s ║\n" "Metric" "NFS Overhead"
        printf "╠═══════════════════════════════╬═══════════════════════════════╣\n"
        printf "║ %-29s ║ %24s%% slower ║\n" "Throughput" "$throughput_overhead"
        printf "║ %-29s ║ %24s%% higher ║\n" "Average Latency" "$latency_overhead"
        printf "║ %-29s ║ %24s%% higher ║\n" "P95 Latency" "$p95_overhead"
        printf "╚═══════════════════════════════╩═══════════════════════════════╝\n"
        echo ""
    fi
    
    # Data summary
    echo -e "${CYAN}Data Summary${NC}"
    printf "╔══════════════════════╦═══════════════╦═══════════════╗\n"
    printf "║ %-20s ║ %-13s ║ %-13s ║\n" "Storage Type" "Records" "Table Size"
    printf "╠══════════════════════╬═══════════════╬═══════════════╣\n"
    printf "║ %-20s ║ %13s ║ %10s MB ║\n" "Direct Storage" "$direct_records" "$direct_size_mb"
    printf "║ %-20s ║ %13s ║ %10s MB ║\n" "NFS Storage" "$nfs_records" "$nfs_size_mb"
    printf "╚══════════════════════╩═══════════════╩═══════════════╝\n"
    echo ""
    
    # Show comparison only if requested
    if [ "$COMPARISON_ONLY" = true ]; then
        return 0
    fi
    
    # Detailed metrics table
    echo -e "${CYAN}Detailed Metrics${NC}"
    printf "╔════════════════════════════╦═══════════════╦═══════════════╗\n"
    printf "║ %-26s ║ %-13s ║ %-13s ║\n" "Metric" "Direct" "NFS"
    printf "╠════════════════════════════╬═══════════════╬═══════════════╣\n"
    
    # Extract more detailed metrics
    local direct_p50 direct_p90 direct_p99 direct_min direct_max
    local nfs_p50 nfs_p90 nfs_p99 nfs_min nfs_max
    
    direct_p50=$(jq -r '.direct.Metrics.p50_latency / 1000000' "$file" 2>/dev/null | xargs printf "%.1f")
    direct_p90=$(jq -r '.direct.Metrics.p90_latency / 1000000' "$file" 2>/dev/null | xargs printf "%.1f")
    direct_p99=$(jq -r '.direct.Metrics.p99_latency / 1000000' "$file" 2>/dev/null | xargs printf "%.1f")
    direct_min=$(jq -r '.direct.Metrics.min_latency / 1000000' "$file" 2>/dev/null | xargs printf "%.1f")
    direct_max=$(jq -r '.direct.Metrics.max_latency / 1000000' "$file" 2>/dev/null | xargs printf "%.1f")
    
    nfs_p50=$(jq -r '.nfs.Metrics.p50_latency / 1000000' "$file" 2>/dev/null | xargs printf "%.1f")
    nfs_p90=$(jq -r '.nfs.Metrics.p90_latency / 1000000' "$file" 2>/dev/null | xargs printf "%.1f")
    nfs_p99=$(jq -r '.nfs.Metrics.p99_latency / 1000000' "$file" 2>/dev/null | xargs printf "%.1f")
    nfs_min=$(jq -r '.nfs.Metrics.min_latency / 1000000' "$file" 2>/dev/null | xargs printf "%.1f")
    nfs_max=$(jq -r '.nfs.Metrics.max_latency / 1000000' "$file" 2>/dev/null | xargs printf "%.1f")
    
    printf "║ %-26s ║ %10s ms ║ %10s ms ║\n" "P50 Latency (Median)" "$direct_p50" "$nfs_p50"
    printf "║ %-26s ║ %10s ms ║ %10s ms ║\n" "P90 Latency" "$direct_p90" "$nfs_p90"
    printf "║ %-26s ║ %10s ms ║ %10s ms ║\n" "P99 Latency" "$direct_p99" "$nfs_p99"
    printf "║ %-26s ║ %10s ms ║ %10s ms ║\n" "Min Latency" "$direct_min" "$nfs_min"
    printf "║ %-26s ║ %10s ms ║ %10s ms ║\n" "Max Latency" "$direct_max" "$nfs_max"
    printf "╚════════════════════════════╩═══════════════╩═══════════════╝\n"
    echo ""
    
    print_success "Results displayed successfully!"
}

# Function to generate CSV output
show_csv_format() {
    local file="$1"
    
    if ! command -v jq >/dev/null 2>&1; then
        print_error "jq is required for CSV format. Install with: brew install jq"
        return 1
    fi
    
    echo "storage_type,throughput_ops_per_sec,avg_latency_ms,p50_latency_ms,p90_latency_ms,p95_latency_ms,p99_latency_ms,min_latency_ms,max_latency_ms,duration_sec,total_operations,records_inserted,table_size_mb"
    
    # Direct storage row
    jq -r '[
        "direct",
        .direct.Metrics.operations_per_second,
        (.direct.Metrics.average_latency / 1000000),
        (.direct.Metrics.p50_latency / 1000000),
        (.direct.Metrics.p90_latency / 1000000),
        (.direct.Metrics.p95_latency / 1000000),
        (.direct.Metrics.p99_latency / 1000000),
        (.direct.Metrics.min_latency / 1000000),
        (.direct.Metrics.max_latency / 1000000),
        (.direct.Duration / 1000000000),
        .direct.Metrics.total_operations,
        .direct.DBStats.final_record_count,
        (.direct.DBStats.table_size_bytes / 1024 / 1024)
    ] | @csv' "$file"
    
    # NFS storage row
    jq -r '[
        "nfs",
        .nfs.Metrics.operations_per_second,
        (.nfs.Metrics.average_latency / 1000000),
        (.nfs.Metrics.p50_latency / 1000000),
        (.nfs.Metrics.p90_latency / 1000000),
        (.nfs.Metrics.p95_latency / 1000000),
        (.nfs.Metrics.p99_latency / 1000000),
        (.nfs.Metrics.min_latency / 1000000),
        (.nfs.Metrics.max_latency / 1000000),
        (.nfs.Duration / 1000000000),
        .nfs.Metrics.total_operations,
        .nfs.DBStats.final_record_count,
        (.nfs.DBStats.table_size_bytes / 1024 / 1024)
    ] | @csv' "$file"
}

# Function to generate HTML output with charts
show_html_format() {
    local file="$1"
    local include_charts="$2"
    
    if ! command -v jq >/dev/null 2>&1; then
        print_error "jq is required for HTML format. Install with: brew install jq"
        return 1
    fi
    
    # Extract data using jq
    local direct_ops direct_latency direct_p95 nfs_ops nfs_latency nfs_p95
    direct_ops=$(jq -r '.direct.Metrics.operations_per_second' "$file")
    direct_latency=$(jq -r '.direct.Metrics.average_latency / 1000000' "$file")
    direct_p95=$(jq -r '.direct.Metrics.p95_latency / 1000000' "$file")
    nfs_ops=$(jq -r '.nfs.Metrics.operations_per_second' "$file")
    nfs_latency=$(jq -r '.nfs.Metrics.average_latency / 1000000' "$file")
    nfs_p95=$(jq -r '.nfs.Metrics.p95_latency / 1000000' "$file")
    
    cat << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>NFS vs Direct Storage Benchmark Results</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
            line-height: 1.6;
            margin: 0;
            padding: 20px;
            background-color: #f5f5f7;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
            background: white;
            padding: 30px;
            border-radius: 12px;
            box-shadow: 0 4px 20px rgba(0,0,0,0.1);
        }
        h1 {
            color: #1d1d1f;
            text-align: center;
            margin-bottom: 30px;
            font-size: 2.5em;
        }
        .metrics-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        .metric-card {
            background: #f8f9fa;
            border-radius: 8px;
            padding: 20px;
            text-align: center;
            border-left: 4px solid #007aff;
        }
        .metric-card.nfs {
            border-left-color: #ff6b35;
        }
        .metric-value {
            font-size: 2em;
            font-weight: bold;
            color: #1d1d1f;
            margin: 10px 0;
        }
        .metric-label {
            color: #86868b;
            font-size: 0.9em;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }
        .comparison-table {
            width: 100%;
            border-collapse: collapse;
            margin: 20px 0;
            background: white;
            border-radius: 8px;
            overflow: hidden;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        .comparison-table th {
            background: #007aff;
            color: white;
            padding: 15px;
            text-align: left;
            font-weight: 600;
        }
        .comparison-table td {
            padding: 12px 15px;
            border-bottom: 1px solid #eee;
        }
        .comparison-table tbody tr:hover {
            background-color: #f8f9fa;
        }
        .performance-impact {
            background: #fff3cd;
            border: 1px solid #ffeaa7;
            border-radius: 8px;
            padding: 20px;
            margin: 20px 0;
        }
        .performance-impact h3 {
            color: #856404;
            margin-top: 0;
        }
        .impact-value {
            font-size: 1.5em;
            font-weight: bold;
            color: #dc3545;
        }
        .chart-container {
            margin: 30px 0;
            text-align: center;
        }
        .timestamp {
            text-align: center;
            color: #86868b;
            font-size: 0.9em;
            margin-top: 30px;
        }
    </style>
$([ "$include_charts" = true ] && cat << 'CHART_SCRIPT'
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
CHART_SCRIPT
)
</head>
<body>
    <div class="container">
        <h1>📊 NFS vs Direct Storage Benchmark</h1>
        
        <div class="metrics-grid">
            <div class="metric-card">
                <div class="metric-label">Direct Storage Throughput</div>
                <div class="metric-value">$(printf "%.1f" "$direct_ops") ops/s</div>
            </div>
            <div class="metric-card nfs">
                <div class="metric-label">NFS Storage Throughput</div>
                <div class="metric-value">$(printf "%.1f" "$nfs_ops") ops/s</div>
            </div>
            <div class="metric-card">
                <div class="metric-label">Direct Avg Latency</div>
                <div class="metric-value">$(printf "%.1f" "$direct_latency") ms</div>
            </div>
            <div class="metric-card nfs">
                <div class="metric-label">NFS Avg Latency</div>
                <div class="metric-value">$(printf "%.1f" "$nfs_latency") ms</div>
            </div>
        </div>

EOF

    # Performance impact section  
    if command -v bc >/dev/null 2>&1; then
        local throughput_overhead raw_direct_ops raw_nfs_ops
        # Use raw JSON values for precise calculation
        raw_direct_ops=$(jq -r '.direct.Metrics.operations_per_second' "$file" 2>/dev/null)
        raw_nfs_ops=$(jq -r '.nfs.Metrics.operations_per_second' "$file" 2>/dev/null)
        throughput_overhead=$(echo "scale=5; (($raw_direct_ops - $raw_nfs_ops) / $raw_direct_ops) * 100" | bc -l | xargs printf "%.2f")
        
        cat << EOF
        <div class="performance-impact">
            <h3>Performance Impact</h3>
            <p>NFS storage shows <span class="impact-value">$throughput_overhead% lower throughput</span> compared to direct storage.</p>
        </div>
EOF
    fi

    # Comparison table
    cat << EOF
        <table class="comparison-table">
            <thead>
                <tr>
                    <th>Metric</th>
                    <th>Direct Storage</th>
                    <th>NFS Storage</th>
                    <th>Difference</th>
                </tr>
            </thead>
            <tbody>
EOF

    # Generate table rows with jq
    jq -r --arg direct_ops "$direct_ops" --arg nfs_ops "$nfs_ops" '
    [
        ["Throughput (ops/sec)", (.direct.Metrics.operations_per_second | tostring + " ops/s"), (.nfs.Metrics.operations_per_second | tostring + " ops/s"), (((.direct.Metrics.operations_per_second - .nfs.Metrics.operations_per_second) / .direct.Metrics.operations_per_second * 100) | tostring + "% slower")],
        ["Average Latency", ((.direct.Metrics.average_latency / 1000000) | tostring + " ms"), ((.nfs.Metrics.average_latency / 1000000) | tostring + " ms"), (((.nfs.Metrics.average_latency - .direct.Metrics.average_latency) / .direct.Metrics.average_latency * 100) | tostring + "% higher")],
        ["P95 Latency", ((.direct.Metrics.p95_latency / 1000000) | tostring + " ms"), ((.nfs.Metrics.p95_latency / 1000000) | tostring + " ms"), (((.nfs.Metrics.p95_latency - .direct.Metrics.p95_latency) / .direct.Metrics.p95_latency * 100) | tostring + "% higher")],
        ["Total Operations", (.direct.Metrics.total_operations | tostring), (.nfs.Metrics.total_operations | tostring), ((.direct.Metrics.total_operations - .nfs.Metrics.total_operations) | tostring + " fewer")]
    ] | .[] | "<tr><td>" + .[0] + "</td><td>" + .[1] + "</td><td>" + .[2] + "</td><td>" + .[3] + "</td></tr>"' "$file"

    cat << EOF
            </tbody>
        </table>
EOF

    # Add charts if requested
    if [ "$include_charts" = true ]; then
        cat << 'EOF'
        <div class="chart-container">
            <canvas id="throughputChart" width="400" height="200"></canvas>
        </div>
        
        <div class="chart-container">
            <canvas id="latencyChart" width="400" height="200"></canvas>
        </div>

        <script>
        // Throughput Chart
        const throughputCtx = document.getElementById('throughputChart').getContext('2d');
        new Chart(throughputCtx, {
            type: 'bar',
            data: {
                labels: ['Direct Storage', 'NFS Storage'],
                datasets: [{
                    label: 'Throughput (ops/sec)',
                    data: [
EOF
        echo "                        $direct_ops,"
        echo "                        $nfs_ops"
        cat << 'EOF'
                    ],
                    backgroundColor: ['#007aff', '#ff6b35'],
                    borderColor: ['#005cbf', '#e55a2b'],
                    borderWidth: 2
                }]
            },
            options: {
                responsive: true,
                plugins: {
                    title: {
                        display: true,
                        text: 'Throughput Comparison'
                    }
                },
                scales: {
                    y: {
                        beginAtZero: true,
                        title: {
                            display: true,
                            text: 'Operations per Second'
                        }
                    }
                }
            }
        });

        // Latency Chart
        const latencyCtx = document.getElementById('latencyChart').getContext('2d');
        new Chart(latencyCtx, {
            type: 'bar',
            data: {
                labels: ['Direct Storage', 'NFS Storage'],
                datasets: [{
                    label: 'Average Latency (ms)',
                    data: [
EOF
        echo "                        $direct_latency,"
        echo "                        $nfs_latency"
        cat << 'EOF'
                    ],
                    backgroundColor: ['#28a745', '#dc3545'],
                    borderColor: ['#1e7e34', '#c82333'],
                    borderWidth: 2
                }]
            },
            options: {
                responsive: true,
                plugins: {
                    title: {
                        display: true,
                        text: 'Average Latency Comparison'
                    }
                },
                scales: {
                    y: {
                        beginAtZero: true,
                        title: {
                            display: true,
                            text: 'Latency (milliseconds)'
                        }
                    }
                }
            }
        });
        </script>
EOF
    fi

    cat << EOF
        
        <div class="timestamp">
            Generated on $(date)
        </div>
    </div>
</body>
</html>
EOF
}

# Function to show JSON format
show_json_format() {
    local file="$1"
    
    if ! command -v jq >/dev/null 2>&1; then
        print_error "jq is required for JSON format. Install with: brew install jq"
        return 1
    fi
    
    jq . "$file"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--format)
            FORMAT="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -c|--charts)
            SHOW_CHARTS=true
            shift
            ;;
        -C|--comparison-only)
            COMPARISON_ONLY=true
            shift
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
            RESULTS_FILE="$1"
            shift
            ;;
    esac
done

# Main execution
main() {
    # Find results file if not specified
    if [ -z "$RESULTS_FILE" ]; then
        RESULTS_FILE=$(find_latest_results)
        print_status "Using latest results file: $RESULTS_FILE"
    elif [ ! -f "$RESULTS_FILE" ]; then
        print_error "Results file not found: $RESULTS_FILE"
        exit 1
    fi
    
    # Validate format
    case $FORMAT in
        table|csv|html|json)
            ;;
        *)
            print_error "Unsupported format: $FORMAT"
            show_usage
            exit 1
            ;;
    esac
    
    # Generate output
    local output=""
    case $FORMAT in
        table)
            if [ -n "$OUTPUT_FILE" ]; then
                show_table_format "$RESULTS_FILE" > "$OUTPUT_FILE"
                print_success "Table saved to: $OUTPUT_FILE"
            else
                show_table_format "$RESULTS_FILE"
            fi
            ;;
        csv)
            output=$(show_csv_format "$RESULTS_FILE")
            ;;
        html)
            output=$(show_html_format "$RESULTS_FILE" "$SHOW_CHARTS")
            ;;
        json)
            output=$(show_json_format "$RESULTS_FILE")
            ;;
    esac
    
    # Save to file if specified
    if [ -n "$OUTPUT_FILE" ] && [ "$FORMAT" != "table" ]; then
        echo "$output" > "$OUTPUT_FILE"
        print_success "Results saved to: $OUTPUT_FILE"
        
        # Show additional info for HTML with charts
        if [ "$FORMAT" = "html" ] && [ "$SHOW_CHARTS" = true ]; then
            print_status "Open $OUTPUT_FILE in your web browser to view the interactive charts"
        fi
    elif [ "$FORMAT" != "table" ]; then
        echo "$output"
    fi
}

main "$@"
