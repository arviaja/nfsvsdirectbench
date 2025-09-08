#!/bin/bash

# NFS vs Direct Storage Benchmark Runner
# This script handles the complete lifecycle: setup, execution, and cleanup

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
DATABASES="postgresql"
SCENARIOS="heavy_inserts"
OUTPUT_DIR=""
VERBOSE=false
CLEANUP_ONLY=false
NO_CLEANUP=false

# Function to print colored output
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

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
    -d, --databases DATABASES    Comma-separated list of databases (default: postgresql)
    -s, --scenarios SCENARIOS    Comma-separated list of scenarios (default: heavy_inserts)
    -o, --output OUTPUT_DIR      Output directory for results
    -v, --verbose               Enable verbose output
    -c, --cleanup-only          Only cleanup running services and exit
    -n, --no-cleanup            Don't cleanup services after benchmark (for debugging)
    -h, --help                  Show this help message

Examples:
    $0                          # Run default benchmark
    $0 -d postgresql -s heavy_inserts -v
    $0 --cleanup-only           # Just cleanup any running services
    $0 --no-cleanup -v          # Run benchmark but keep services running

Available databases: postgresql, mysql, sqlite
Available scenarios: heavy_inserts, mixed_workload_70_30, mixed_workload_50_50, transaction_heavy, bulk_import
EOF
}

# Function to cleanup services
cleanup_services() {
    print_status "Shutting down benchmark services..."
    
    if docker-compose ps -q | grep -q .; then
        docker-compose down --remove-orphans
        print_success "All benchmark services stopped"
    else
        print_status "No benchmark services were running"
    fi
    
    # Optional: Remove volumes (uncomment if you want to clear all data)
    # print_status "Removing benchmark volumes..."
    # docker-compose down -v
}

# Function to setup trap for cleanup on exit
setup_cleanup_trap() {
    if [ "$NO_CLEANUP" = false ]; then
        trap 'cleanup_services; exit' INT TERM EXIT
    fi
}

# Function to start services
start_services() {
    print_status "Starting benchmark infrastructure..."
    
    # Check if docker-compose.yml exists
    if [ ! -f "docker-compose.yml" ]; then
        print_error "docker-compose.yml not found. Please run this script from the project root directory."
        exit 1
    fi
    
    # Start services
    print_status "Building and starting Docker containers..."
    docker-compose up -d --build
    
    # Wait for services to be healthy
    print_status "Waiting for services to become healthy..."
    local max_wait=300  # 5 minutes
    local waited=0
    
    while [ $waited -lt $max_wait ]; do
        if docker-compose ps | grep -q "(unhealthy)"; then
            print_warning "Some services are still starting... (${waited}s elapsed)"
            sleep 10
            waited=$((waited + 10))
        elif docker-compose ps | grep -q "(health: starting)"; then
            print_status "Health checks starting... (${waited}s elapsed)"
            sleep 5
            waited=$((waited + 5))
        else
            # Check if all expected services are healthy
            local healthy_count=$(docker-compose ps --filter "status=running" | grep -c "(healthy)" || echo "0")
            local expected_services=6  # nfs-server, postgres-direct, postgres-nfs, mysql-direct, mysql-nfs, sqlite-runner, benchmark-runner
            
            if [ $healthy_count -ge $expected_services ]; then
                print_success "All services are healthy and ready!"
                return 0
            else
                print_status "Waiting for remaining services to be healthy... ($healthy_count/$expected_services ready)"
                sleep 5
                waited=$((waited + 5))
            fi
        fi
    done
    
    print_error "Timeout waiting for services to become healthy"
    print_status "Current service status:"
    docker-compose ps
    exit 1
}

# Function to run benchmark
run_benchmark() {
    print_status "Running benchmark with databases: $DATABASES, scenarios: $SCENARIOS"
    
    local cmd="docker-compose exec -T benchmark-runner /usr/local/bin/nfsbench run --config /app/config/default.yaml"
    
    if [ -n "$DATABASES" ]; then
        cmd="$cmd -d $DATABASES"
    fi
    
    if [ -n "$SCENARIOS" ]; then
        cmd="$cmd -s $SCENARIOS"
    fi
    
    if [ -n "$OUTPUT_DIR" ]; then
        cmd="$cmd -o $OUTPUT_DIR"
    fi
    
    if [ "$VERBOSE" = true ]; then
        cmd="$cmd --verbose"
    fi
    
    print_status "Executing: $cmd"
    
    # Run the benchmark
    if eval $cmd; then
        print_success "Benchmark completed successfully!"
        
        # Show results location
        print_status "Results saved to:"
        docker-compose exec -T benchmark-runner find /app/results -name "*.json" -type f 2>/dev/null || true
        
        return 0
    else
        print_error "Benchmark failed!"
        return 1
    fi
}

# Function to show results summary
show_results() {
    print_status "Benchmark Results Summary:"
    
    # Try to get the latest results
    local results_dir="./results"
    if [ -d "$results_dir" ]; then
        local latest_result=$(find "$results_dir" -name "*.json" -type f | head -1)
        if [ -n "$latest_result" ] && [ -f "$latest_result" ]; then
            echo ""
            echo "📊 Results file: $latest_result"
            echo ""
            
            # Extract key metrics if jq is available
            if command -v jq >/dev/null 2>&1; then
                echo "🚀 Performance Summary:"
                echo "  Direct Storage:"
                jq -r '.direct | "    - Throughput: \(.Metrics.operations_per_second | round) ops/sec"' "$latest_result" 2>/dev/null || true
                jq -r '.direct | "    - Avg Latency: \(.Metrics.average_latency / 1000000 | round)ms"' "$latest_result" 2>/dev/null || true
                jq -r '.direct | "    - P95 Latency: \(.Metrics.p95_latency / 1000000 | round)ms"' "$latest_result" 2>/dev/null || true
                
                echo "  NFS Storage:"
                jq -r '.nfs | "    - Throughput: \(.Metrics.operations_per_second | round) ops/sec"' "$latest_result" 2>/dev/null || true
                jq -r '.nfs | "    - Avg Latency: \(.Metrics.average_latency / 1000000 | round)ms"' "$latest_result" 2>/dev/null || true
                jq -r '.nfs | "    - P95 Latency: \(.Metrics.p95_latency / 1000000 | round)ms"' "$latest_result" 2>/dev/null || true
                
                # Calculate performance impact
                local direct_ops=$(jq -r '.direct.Metrics.operations_per_second' "$latest_result" 2>/dev/null || echo "0")
                local nfs_ops=$(jq -r '.nfs.Metrics.operations_per_second' "$latest_result" 2>/dev/null || echo "0")
                
                if [ "$direct_ops" != "0" ] && [ "$nfs_ops" != "0" ]; then
                    local impact=$(echo "scale=1; (($direct_ops - $nfs_ops) / $direct_ops) * 100" | bc -l 2>/dev/null || echo "N/A")
                    echo "  📉 NFS Performance Impact: ${impact}% lower throughput"
                fi
            fi
        fi
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--databases)
            DATABASES="$2"
            shift 2
            ;;
        -s|--scenarios)
            SCENARIOS="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -c|--cleanup-only)
            CLEANUP_ONLY=true
            shift
            ;;
        -n|--no-cleanup)
            NO_CLEANUP=true
            shift
            ;;
        -h|--help)
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

# Main execution
main() {
    print_status "NFS vs Direct Storage Benchmark Runner"
    echo ""
    
    # Check if we're in the right directory
    if [ ! -f "docker-compose.yml" ]; then
        print_error "docker-compose.yml not found. Please run this script from the project root directory."
        exit 1
    fi
    
    # If cleanup-only mode, just cleanup and exit
    if [ "$CLEANUP_ONLY" = true ]; then
        cleanup_services
        exit 0
    fi
    
    # Setup cleanup trap unless disabled
    setup_cleanup_trap
    
    # Start services
    start_services
    
    # Run benchmark
    if run_benchmark; then
        show_results
        print_success "Benchmark completed successfully!"
        exit_code=0
    else
        print_error "Benchmark failed!"
        exit_code=1
    fi
    
    # Manual cleanup if trap is disabled
    if [ "$NO_CLEANUP" = false ]; then
        cleanup_services
    else
        print_warning "Services left running for debugging (use --cleanup-only to stop them later)"
    fi
    
    exit $exit_code
}

# Run main function
main "$@"
