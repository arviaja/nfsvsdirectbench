#!/bin/bash

# Emergency cleanup script for NFS vs Direct Storage Benchmark
# Use this to forcefully stop all benchmark services

set -euo pipefail

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

# Safety function to show all containers for transparency
show_safety_info() {
    print_status "Container safety check - All running Docker containers:"
    docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" | head -10
    echo ""
    print_status "This cleanup will ONLY affect containers managed by this project's docker-compose.yml"
    local nfsbench_containers=$(docker ps -q --filter "name=^/nfsbench-" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$nfsbench_containers" -gt 0 ]; then
        echo "Benchmark containers that will be stopped:"
        docker ps --filter "name=^/nfsbench-" --format "  ✗ {{.Names}} ({{.Image}})"
    else
        echo "No benchmark containers currently running."
    fi
    echo ""
}

main() {
    print_status "Emergency cleanup of NFS benchmark services"
    echo ""
    
    # Check if we're in the right directory
    if [ ! -f "docker-compose.yml" ]; then
        print_error "docker-compose.yml not found. Please run this script from the project root directory."
        exit 1
    fi
    
    # Show safety information
    show_safety_info
    
    # Show current services
    print_status "Current benchmark services:"
    if docker-compose ps -q | grep -q .; then
        docker-compose ps
        echo ""
        
        # Show which specific containers will be affected
        print_status "The following containers will be stopped:"
        docker ps --filter "name=^/nfsbench-" --format "  - {{.Names}} ({{.Image}})"
        echo ""
    else
        print_status "No benchmark services found running"
        
        # Double-check for any stray containers with our specific naming pattern
        local stray_containers=$(docker ps -q --filter "name=^/nfsbench-" 2>/dev/null | wc -l | tr -d ' ')
        if [ "$stray_containers" -gt 0 ]; then
            print_warning "Found stray nfsbench containers not managed by docker-compose:"
            docker ps --filter "name=^/nfsbench-" --format "  - {{.Names}} ({{.Image}})"
            print_status "Cleaning up stray containers (only those starting with 'nfsbench-')..."
            local stray_ids=$(docker ps -q --filter "name=^/nfsbench-" 2>/dev/null)
            if [ -n "$stray_ids" ]; then
                echo "$stray_ids" | xargs -r docker stop 2>/dev/null || true
                echo "$stray_ids" | xargs -r docker rm 2>/dev/null || true
            fi
            print_success "Stray containers cleaned up"
        fi
        exit 0
    fi
    
    # Stop services using docker-compose (safest method)
    print_status "Stopping benchmark services using docker-compose..."
    docker-compose down --remove-orphans
    
    # Optional: Also remove volumes (uncomment if needed)
    if [ "${1:-}" = "--remove-volumes" ] || [ "${1:-}" = "-v" ]; then
        print_warning "Removing all benchmark volumes and data..."
        docker-compose down -v
        print_success "All services and volumes removed"
    else
        print_success "All benchmark services stopped"
        print_status "Use '$0 --remove-volumes' to also remove data volumes"
    fi
    
    # Show final status
    print_status "Final status check:"
    if docker-compose ps -q | grep -q .; then
        print_warning "Some services may still be stopping..."
        docker-compose ps
    else
        print_success "All benchmark services are stopped"
    fi
}

# Show usage if requested
if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    cat << EOF
Usage: $0 [OPTIONS]

Emergency cleanup script for NFS benchmark services.

Options:
    -v, --remove-volumes    Also remove data volumes (WARNING: destroys all data)
    -h, --help             Show this help message

Examples:
    $0                     # Stop all benchmark services
    $0 --remove-volumes    # Stop services and remove all data
EOF
    exit 0
fi

main "$@"
