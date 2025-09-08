#!/bin/bash
# Check system dependencies for NFS benchmark

set -e

echo "Checking system dependencies..."

# Check Docker
if ! command -v docker &> /dev/null; then
    echo "ERROR: Docker not found"
    echo "Install: https://docs.docker.com/get-docker/"
    exit 1
fi

echo "Docker: $(docker --version)"

# Check Docker Compose
if ! command -v docker-compose &> /dev/null; then
    echo "ERROR: docker-compose not found"
    echo "Install: https://docs.docker.com/compose/install/"
    exit 1
fi

echo "Docker Compose: $(docker-compose --version)"

# Check Docker daemon
if ! docker info &> /dev/null; then
    echo "ERROR: Docker daemon not running"
    echo "Start Docker Desktop or docker daemon"
    exit 1
fi

echo "Docker daemon: running"

# Check available disk space (10GB minimum)
AVAILABLE=$(df . | tail -1 | awk '{print $4}')
if [ "$AVAILABLE" -lt 10485760 ]; then
    echo "WARNING: Less than 10GB disk space available"
    echo "Available: $(($AVAILABLE / 1024 / 1024))GB"
fi

# Check available memory (4GB minimum)
if command -v free &> /dev/null; then
    MEMORY=$(free -m | awk 'NR==2{print $7}')
    if [ "$MEMORY" -lt 4000 ]; then
        echo "WARNING: Less than 4GB memory available"
        echo "Available: ${MEMORY}MB"
    fi
elif [ -f /proc/meminfo ]; then
    MEMORY=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo)
    if [ "$MEMORY" -lt 4000 ]; then
        echo "WARNING: Less than 4GB memory available"
        echo "Available: ${MEMORY}MB"
    fi
fi

# Check Go (optional)
if command -v go &> /dev/null; then
    echo "Go: $(go version)"
else
    echo "INFO: Go not found (optional for local development)"
fi

echo "All required dependencies satisfied"
