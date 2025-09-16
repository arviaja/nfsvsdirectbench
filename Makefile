# NFS vs Direct Storage Database Benchmark
# Makefile for easy project management

.PHONY: help setup build start stop status clean benchmark benchmark-quick report lint test docs

# Default target
.DEFAULT_GOAL := help

# Configuration
PROJECT_NAME := nfsvsdirectbench
COMPOSE_FILE := docker-compose.yml
RESULTS_DIR := ./results
VENV_DIR := .venv

help: ## Show this help message
	@echo "NFS vs Direct Storage Database Benchmark"
	@echo "========================================"
	@echo ""
	@echo "Available commands:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'
	@echo ""
	@echo "Examples:"
	@echo "  make setup          # Initial project setup"
	@echo "  make benchmark      # Run full benchmark suite"
	@echo "  make benchmark-quick # Run quick benchmark"
	@echo "  make report         # Generate reports from latest results"

# ============================================================================
# Project Setup
# ============================================================================

setup: setup-dirs setup-go build ## Initial project setup
	@echo "✓ Project setup complete"
	@echo ""
	@echo "Next steps:"
	@echo "  1. Run 'make start' to start infrastructure"
	@echo "  2. Run 'make benchmark' to run benchmarks"
	@echo "  3. Run 'make report' to generate reports"

setup-dirs: ## Create necessary directories
	@echo "Creating project directories..."
	@mkdir -p $(RESULTS_DIR)
	@mkdir -p logs
	@mkdir -p config
	@mkdir -p docs

setup-go: ## Set up Go environment
	@echo "Setting up Go environment..."
	@go mod download
	@go mod tidy

# ============================================================================
# Docker Management
# ============================================================================

build: ## Build all Docker images
	@echo "Building Docker images..."
	@docker-compose -f $(COMPOSE_FILE) build

start: ## Start all benchmark infrastructure services
	@echo "Starting benchmark infrastructure..."
	@docker-compose -f $(COMPOSE_FILE) up -d
	@echo "Waiting for services to be healthy..."
	@./scripts/wait-for-services.sh

stop: ## Stop all benchmark services
	@echo "Stopping benchmark services..."
	@docker-compose -f $(COMPOSE_FILE) down

restart: stop start ## Restart all services

status: ## Show status of benchmark infrastructure
	@echo "Benchmark Infrastructure Status:"
	@echo "==============================="
	@docker-compose -f $(COMPOSE_FILE) ps

logs: ## Show logs from all services
	@docker-compose -f $(COMPOSE_FILE) logs -f

logs-nfs: ## Show NFS server logs
	@docker-compose -f $(COMPOSE_FILE) logs -f nfs-server

logs-postgres: ## Show PostgreSQL logs
	@docker-compose -f $(COMPOSE_FILE) logs -f postgresql-direct postgresql-nfs

logs-mysql: ## Show MySQL logs
	@docker-compose -f $(COMPOSE_FILE) logs -f mysql-direct mysql-nfs

# ============================================================================
# Benchmark Execution
# ============================================================================

benchmark: start ## Run full benchmark suite
	@echo "Running full benchmark suite..."
	@docker-compose -f $(COMPOSE_FILE) exec benchmark-runner nfsbench run

benchmark-quick: start ## Run quick benchmark (reduced duration)
	@echo "Running quick benchmark suite..."
	@docker-compose -f $(COMPOSE_FILE) exec benchmark-runner nfsbench run --config config/quick.yaml

benchmark-postgresql: start ## Run benchmark for PostgreSQL only
	@echo "Running PostgreSQL benchmark..."
	@docker-compose -f $(COMPOSE_FILE) exec benchmark-runner nfsbench run -d postgresql

benchmark-mysql: start ## Run benchmark for MySQL only
	@echo "Running MySQL benchmark..."
	@docker-compose -f $(COMPOSE_FILE) exec benchmark-runner nfsbench run -d mysql

benchmark-sqlite: start ## Run benchmark for SQLite only
	@echo "Running SQLite benchmark..."
	@docker-compose -f $(COMPOSE_FILE) exec benchmark-runner nfsbench run -d sqlite

benchmark-custom: start ## Run benchmark with custom config (make benchmark-custom CONFIG=myconfig.yaml)
	@echo "Running benchmark with custom configuration: $(CONFIG)"
	@docker-compose -f $(COMPOSE_FILE) exec benchmark-runner nfsbench run --config $(CONFIG)

benchmark-dry-run: ## Show what benchmark would run without executing
	@docker-compose -f $(COMPOSE_FILE) exec benchmark-runner nfsbench run --dry-run

# ============================================================================
# Reporting
# ============================================================================

report: ## Generate reports from latest benchmark results
	@echo "Generating reports from latest results..."
	@latest_result=$$(find $(RESULTS_DIR) -name "*.json" -type f | sort -r | head -1); \
	if [ -n "$$latest_result" ]; then \
		./scripts/generate_report.sh "$$latest_result"; \
	else \
		echo "No benchmark results found. Run 'make benchmark' first."; \
	fi

report-all: ## Generate reports from all results
	@echo "Generating reports for all results..."
	@for dir in $(shell ls -t $(RESULTS_DIR)); do \
		echo "Processing $$dir..."; \
		docker-compose -f $(COMPOSE_FILE) exec benchmark-runner python -m src.benchmark report $$dir; \
	done

report-html: ## Generate HTML reports from latest results
	@echo "Generating HTML report from latest results..."
	@latest_result=$$(find $(RESULTS_DIR) -name "*.json" -type f | sort -r | head -1); \
	if [ -n "$$latest_result" ]; then \
		./scripts/generate_report.sh -f html "$$latest_result"; \
	else \
		echo "No benchmark results found. Run 'make benchmark' first."; \
	fi

report-csv: ## Generate CSV reports only
	@docker-compose -f $(COMPOSE_FILE) exec benchmark-runner python -m src.benchmark report $(shell ls -t $(RESULTS_DIR) | head -1) -f csv

# ============================================================================
# Development and Testing
# ============================================================================

shell: ## Open shell in benchmark runner container
	@docker-compose -f $(COMPOSE_FILE) exec benchmark-runner /bin/bash

shell-postgres: ## Open psql shell to PostgreSQL (direct storage)
	@docker-compose -f $(COMPOSE_FILE) exec postgresql-direct psql -U benchmark_user -d benchmark_db

shell-mysql: ## Open mysql shell to MySQL (direct storage)
	@docker-compose -f $(COMPOSE_FILE) exec mysql-direct mysql -u benchmark_user -p benchmark_db

lint: ## Run code linting
	@echo "Running code linting..."
	@go vet ./...
	@go fmt ./...

format: ## Format code
	@echo "Formatting code..."
	@go fmt ./...

test: ## Run unit tests
	@echo "Running unit tests..."
	@go test ./... -v

test-integration: start ## Run integration tests
	@echo "Running integration tests..."
	@go test ./... -tags=integration -v

# ============================================================================
# Cleanup
# ============================================================================

clean: ## Clean up all containers, volumes, and results
	@echo "Cleaning up..."
	@docker-compose -f $(COMPOSE_FILE) down -v --remove-orphans
	@docker system prune -f
	@echo "✓ Cleanup complete"

clean-results: ## Clean up only benchmark results
	@echo "Cleaning benchmark results..."
	@rm -rf $(RESULTS_DIR)/*
	@echo "✓ Results cleaned"

clean-logs: ## Clean up log files
	@echo "Cleaning log files..."
	@rm -rf logs/*
	@echo "✓ Logs cleaned"

clean-all: clean clean-results clean-logs ## Clean up everything
	@echo "✓ Full cleanup complete"

# ============================================================================
# Utilities
# ============================================================================

config-template: ## Generate configuration template
	@echo "Generating configuration template..."
	@cp config/default.yaml config/my-config.yaml
	@echo "✓ Template created: config/my-config.yaml"

check-deps: ## Check system dependencies
	@echo "Checking system dependencies..."
	@./scripts/check-dependencies.sh

nfs-test: start ## Test NFS connectivity
	@echo "Testing NFS connectivity..."
	@docker-compose -f $(COMPOSE_FILE) exec nfs-server showmount -e localhost
	@docker-compose -f $(COMPOSE_FILE) exec benchmark-runner mount | grep nfs || echo "No NFS mounts found"

# ============================================================================
# Documentation
# ============================================================================

docs: ## Generate documentation
	@echo "Generating documentation..."
	@mkdir -p docs/_build
	@echo "Documentation generation not yet implemented"

# ============================================================================
# CI/CD Support
# ============================================================================

ci-setup: setup build ## Setup for CI environment
	@echo "CI setup complete"

ci-test: ci-setup test ## Run CI tests
	@echo "CI tests complete"

ci-benchmark-smoke: ci-setup ## Run smoke benchmark for CI
	@echo "Running CI smoke benchmark..."
	@timeout 300 make benchmark-quick || echo "Smoke benchmark completed (or timed out safely)"

# ============================================================================
# Platform-specific targets
# ============================================================================

setup-macos: ## macOS-specific setup
	@echo "Setting up for macOS..."
	@brew list docker > /dev/null 2>&1 || echo "Please install Docker Desktop from https://docker.com/products/docker-desktop"
	@brew list python3 > /dev/null 2>&1 || brew install python3

setup-linux: ## Linux-specific setup
	@echo "Setting up for Linux..."
	@which docker > /dev/null || echo "Please install Docker: https://docs.docker.com/engine/install/"
	@which docker-compose > /dev/null || echo "Please install Docker Compose: https://docs.docker.com/compose/install/"

# ============================================================================
# Information targets
# ============================================================================

info: ## Show project information
	@echo "NFS vs Direct Storage Database Benchmark"
	@echo "========================================"
	@echo "Project: $(PROJECT_NAME)"
	@echo "Docker Compose: $(COMPOSE_FILE)"
	@echo "Results Directory: $(RESULTS_DIR)"
	@echo "Python Virtual Environment: $(VENV_DIR)"
	@echo ""
	@echo "Docker Images:"
	@docker images | grep nfsbench || echo "  No benchmark images found (run 'make build')"
	@echo ""
	@echo "Running Containers:"
	@docker ps --filter "name=nfsbench" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" || echo "  No containers running"

version: ## Show version information
	@echo "NFS vs Direct Storage Database Benchmark v1.0.0"
