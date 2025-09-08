# NFS vs Direct Storage Database Benchmark

A comprehensive benchmark suite designed to demonstrate the performance overhead introduced by NFS (Network File System) protocol when used for database storage compared to direct block storage access.

## Overview

This project provides empirical evidence of NFS overhead in database workloads, addressing the common misconception that "fast network connections" eliminate NFS performance bottlenecks. While NFS may appear adequate for individual operations, the cumulative latency overhead becomes significant in high-throughput database environments.

## Key Features

### Multi-Database Support
- **PostgreSQL**: Full-featured relational database testing
- **MySQL/MariaDB**: Alternative RDBMS comparison
- **SQLite**: Lightweight database for baseline measurements

### Comprehensive Test Scenarios
- **Heavy INSERT Operations**: Bulk data insertion with configurable batch sizes
- **Mixed Read/Write Workloads**: Realistic application patterns (70/30, 50/50, 20/80 ratios)
- **Transaction-Heavy Workloads**: Concurrent transactions with various isolation levels
- **Bulk Import Operations**: Large data set imports using COPY/LOAD commands
- **OLTP Workloads**: Transaction processing using TPC-C-like patterns

### NFS Configuration Testing
- **NFSv3 vs NFSv4**: Protocol version comparison
- **Mount Options**: Testing various performance-affecting options
  - Sync vs Async modes
- Buffer sizes (rsize/wsize)
  - Cache settings (noac, actimeo)
- **Automated Setup**: Local NFS server configuration and mounting

### Detailed Metrics Collection
- **Latency Analysis**: Average, median, P95, P99 measurements
- **Throughput Metrics**: Operations per second, transactions per second
- **System Resources**: CPU, memory, I/O utilization
- **Network Overhead**: Bandwidth usage, packet counts
- **Database-Specific**: Query statistics, lock contention, buffer utilization

### Multiple Output Formats
- **Real-time CLI**: Progress bars and live statistics
- **JSON Reports**: Machine-readable detailed results
- **CSV Exports**: Spreadsheet-compatible data
- **HTML Dashboard**: Interactive charts and comparisons
- **Markdown Summaries**: Human-readable executive summaries

## Quick Start

### Prerequisites
- Docker and Docker Compose
- Go 1.21+ (for building from source)
- 4GB+ available RAM
- 10GB+ available disk space

### Installation

```bash
git clone <repository-url>
cd nfsvsdirectbench
make setup
```

### Basic Usage

**Recommended: Using the automated script (handles setup, execution, and cleanup)**
```bash
# Run default benchmark (PostgreSQL, heavy_inserts) with automatic cleanup
./scripts/run_benchmark.sh

# Run with verbose output
./scripts/run_benchmark.sh --verbose

# Run specific database and scenario
./scripts/run_benchmark.sh -d postgresql -s heavy_inserts -v

# Cleanup any running services
./scripts/cleanup.sh
```

**Alternative: Manual Docker commands**
```bash
# Start all services
docker-compose up -d --build

# Run benchmark manually
docker-compose exec benchmark-runner /usr/local/bin/nfsbench run --config /app/config/default.yaml

# Stop all services
docker-compose down
```

## Scripts & Automation

The project includes automated scripts that handle the complete benchmark lifecycle with proper cleanup:

### `scripts/run_benchmark.sh` - Main Benchmark Runner
- ✅ **Automatic cleanup on completion or failure**
- ✅ **Signal handling** (Ctrl+C cleanup)
- ✅ **Health checks** for all services
- ✅ **Results summary** with performance metrics
- ✅ **Flexible configuration** options

### `scripts/cleanup.sh` - Emergency Cleanup
- 🚨 **Forceful shutdown** of all benchmark services
- 🔒 **Safe operation** - only affects benchmark containers
- 📊 **Status reporting** before and after cleanup

### Safety Features
- **Signal Traps**: Automatic cleanup on script interruption
- **Exit Traps**: Services cleaned up on script completion  
- **Selective Shutdown**: Only benchmark containers affected
- **Health Monitoring**: Wait for services to be ready
- **Error Recovery**: Cleanup even on benchmark failure

### Results Location
Benchmark results are automatically saved to:
```
./results/run_%Y%m%d_%H%M%S/postgresql_heavy_inserts.json
```

## Results Visualization

After running benchmarks, you can visualize the results in several ways:

### 1. Console Table View

```bash
# Show latest results in a formatted table
./scripts/view_results.sh

# Show specific results file
./scripts/view_results.sh results/run_20250101_120000/postgresql_heavy_inserts.json

# Show only performance comparison
./scripts/view_results.sh -C
```

### 2. Export to Different Formats

```bash
# Export to CSV for spreadsheet analysis
./scripts/view_results.sh -f csv -o results.csv

# Generate HTML report with interactive charts
./scripts/view_results.sh -f html -c -o report.html

# Export raw JSON (pretty-formatted)
./scripts/view_results.sh -f json -o results.json
```

### 3. Generate Interactive Charts (Go)

**Prerequisites**: Go 1.21+ (automatically downloads dependencies)

```bash
# Generate all chart types as interactive HTML
./scripts/generate_charts.sh

# Generate specific chart type
./scripts/generate_charts.sh -c throughput
./scripts/generate_charts.sh -c latency  
./scripts/generate_charts.sh -c dashboard

# Save charts to specific directory
./scripts/generate_charts.sh -c all -o charts/
./scripts/generate_charts.sh -c combined
```

**Chart Types Available:**
- `throughput` - Operations per second comparison
- `latency` - Latency distribution (P50, P90, P95, P99) 
- `combined` - Side-by-side throughput and key latency metrics
- `dashboard` - Comprehensive view with all metrics
- `all` - Generate all chart types (default)

**Output**: Interactive HTML files you can open in any web browser

### 4. Comprehensive Reports (Recommended)

Generate detailed reports with **explanations of what each benchmark tests, why it matters, and what the results mean**:

```bash
# Generate a comprehensive markdown report
./scripts/generate_report.sh

# Generate HTML report with charts
./scripts/generate_report.sh -f html

# Generate PDF report
./scripts/generate_report.sh -f pdf

# Use specific results file
./scripts/generate_report.sh results/run_20250101_120000/postgresql_heavy_inserts.json
```

**What makes these reports special:**
- 📚 **Complete explanations** of what each benchmark tests
- 🎯 **Why the comparison matters** for real-world scenarios
- 📊 **What the metrics mean** in practical terms
- 🔍 **Detailed results interpretation** with business impact
- 💡 **Specific recommendations** based on the results
- 📈 **Interactive charts** (when Go is available)

See `scripts/README.md` for detailed usage instructions.

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   PostgreSQL    │    │     MySQL       │    │     SQLite      │
│   Container     │    │   Container     │    │   Container     │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
         ┌─────────────────────────────────────────────┐
         │            Benchmark Runner                 │
         │     (Workload Generation & Metrics)        │
         └─────────────────────────────────────────────┘
                                 │
         ┌─────────────────────────────────────────────┐
         │              Storage Layer                  │
         │                                             │
         │  ┌─────────────────┐  ┌─────────────────┐   │
         │  │ Direct Storage  │  │  NFS Storage    │   │
         │  │   (Volume)      │  │   (NFS Mount)   │   │
         │  └─────────────────┘  └─────────────────┘   │
         └─────────────────────────────────────────────┘
                                 │
                    ┌─────────────────────┐
                    │    NFS Server       │
                    │   (Container)       │
                    └─────────────────────┘
```

## Configuration

The benchmark suite uses YAML configuration files to define test scenarios:

```yaml
databases:
  - postgresql
  - mysql
  - sqlite

storage_types:
  - direct
  - nfs

nfs_versions:
  - v3
  - v4

scenarios:
  - name: "heavy_inserts"
    duration: 300
    threads: 10
    batch_size: 1000
  - name: "mixed_workload"
    duration: 600
    read_ratio: 70
    write_ratio: 30
```

## Results Interpretation

The benchmark generates comparative reports showing:

- **Overhead Percentage**: How much slower NFS is compared to direct storage
- **Statistical Significance**: Whether differences are statistically meaningful
- **Bottleneck Identification**: Which operations are most affected
- **Scaling Impact**: How overhead increases with load

### Example Results

```
Database: PostgreSQL | Scenario: Heavy Inserts
╔══════════════════╦═══════════════╦═══════════════╦══════════════╗
║ Storage Type     ║ Avg Latency   ║ P99 Latency   ║ Throughput   ║
╠══════════════════╬═══════════════╬═══════════════╬══════════════╣
║ Direct Storage   ║ 2.3ms         ║ 15.2ms        ║ 4,250 ops/s  ║
║ NFS v4           ║ 4.1ms (+78%)  ║ 28.9ms (+90%) ║ 2,890 ops/s  ║
╚══════════════════╩═══════════════╩═══════════════╩══════════════╝
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Submit a pull request

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Disclaimer

This benchmark is designed for educational and demonstration purposes. Results may vary based on:
- Hardware configuration
- Network setup
- Operating system
- Docker configuration
- NFS server implementation

Always test in your specific environment for production decisions.
