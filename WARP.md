# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## High-level code architecture and structure

This project is a benchmark suite written in Go to compare the performance of databases running on NFS versus direct-attached storage. The core logic is containerized using Docker and orchestrated with Docker Compose.

- **`cmd/`**: Contains the main applications.
  - **`nfsbench/`**: The primary benchmark runner CLI. It orchestrates the tests, collects metrics, and generates results.
  - **`chartgen/`**: A utility to generate HTML charts from the benchmark result files.
- **`internal/`**: Contains the core logic of the benchmark runner.
  - **`benchmark/`**: Implements the different test scenarios (e.g., heavy inserts, mixed workloads).
  - **`database/`**: Provides connectors and helpers for interacting with PostgreSQL, MySQL, and SQLite.
  - **`metrics/`**: Handles the collection and aggregation of performance data.
  - **`config/`**: Manages the YAML configuration for benchmark runs.
  - **`cli/`**: Defines the command-line interface for `nfsbench`.
- **`scripts/`**: Contains shell scripts for automating common tasks like running benchmarks, cleaning up, and viewing results. These are the primary entry points for most operations.
- **`config/`**: Holds the YAML configuration files that define the benchmark scenarios, databases, and storage types.
- **`docker-compose.yml`**: Defines the services for the benchmark environment, including the databases (PostgreSQL, MySQL), an NFS server, and the benchmark runner itself.
- **`Makefile`**: Provides a convenient way to run common tasks like building, testing, and cleaning up the environment.

The general workflow is to start the Docker containers, run the benchmark via the `nfsbench` tool, and then generate reports from the results.

## Commonly used commands

Here are the most common commands used for developing in this codebase.

### Setup and Building

- **Initial setup**: `make setup`
- **Build Docker images**: `make build`

### Running Benchmarks

- **Run the full benchmark suite**: `make benchmark`
- **Run a quick, reduced-duration benchmark**: `make benchmark-quick`

### Testing

- **Run unit tests**: `make test`
- **Run integration tests (requires Docker environment)**: `make test-integration`

### Linting and Formatting

- **Run the linter**: `make lint`
- **Format the code**: `make format`

### Generating Reports

- **Generate a report from the latest results**: `make report`
- **Generate an HTML report**: `make report-html`

### Cleanup

- **Stop all services**: `make stop`
- **Clean up all containers, volumes, and results**: `make clean`

