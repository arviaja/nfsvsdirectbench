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

```bash
# Build the benchmark binary
make build

# Run full benchmark suite (all databases, all scenarios)
./bin/nfsvsdirectbench --config config/default.yaml

# Run with Docker (recommended)
make benchmark

# Run specific test scenarios
./bin/nfsvsdirectbench --config config/postgresql-only.yaml

# Generate reports from existing results
make reports
```

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
