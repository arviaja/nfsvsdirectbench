#!/bin/bash
# Wait for all benchmark services to be ready

set -e

echo "Waiting for services to be ready..."

# Maximum wait time in seconds
MAX_WAIT=300
WAIT_TIME=0

while [ $WAIT_TIME -lt $MAX_WAIT ]; do
    # Check if all services are running
    UNHEALTHY=$(docker-compose ps | grep -c "unhealthy\|starting" || true)
    if [ "$UNHEALTHY" -gt 0 ]; then
        echo "Some services are still starting, waiting..."
        sleep 10
        WAIT_TIME=$((WAIT_TIME + 10))
    else
        echo "All services are ready!"
        exit 0
    fi
done

echo "Timeout waiting for services to be ready"
docker-compose ps
exit 1
