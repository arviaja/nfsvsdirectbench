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

main() {
    print_status "Emergency cleanup of NFS benchmark services"
    echo ""
    
    # Check if we're in the right directory
    if [ ! -f "docker-compose.yml" ]; then
        print_error "docker-compose.yml not found. Please run this script from the project root directory."
        exit 1
    fi
    
    # Show current services
    print_status "Current benchmark services:"
    if docker-compose ps | grep -q "nfsbench"; then
        docker-compose ps
        echo ""
    else
        print_status "No benchmark services found running"
        exit 0
    fi
    
    # Stop services
    print_status "Stopping all benchmark services..."
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
    if docker-compose ps | grep -q "nfsbench"; then
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
