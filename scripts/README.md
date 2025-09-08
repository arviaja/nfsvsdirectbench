# Benchmark Scripts

This directory contains scripts to manage the NFS vs Direct Storage benchmark lifecycle.

## Scripts Overview

### `run_benchmark.sh` - Main Benchmark Runner

The primary script that handles the complete benchmark lifecycle with automatic cleanup.

**Features:**
- ✅ Automatic service startup and health checks
- ✅ Benchmark execution with configurable options  
- ✅ **Automatic cleanup on completion or failure**
- ✅ **Cleanup on script interruption (Ctrl+C)**
- ✅ Results summary and location display
- ✅ Colorized output for better visibility

**Usage:**
```bash
# Run default benchmark (PostgreSQL, heavy_inserts)
./scripts/run_benchmark.sh

# Run with verbose output
./scripts/run_benchmark.sh --verbose

# Run specific database and scenario
./scripts/run_benchmark.sh -d postgresql -s heavy_inserts -v

# Keep services running for debugging (no auto-cleanup)
./scripts/run_benchmark.sh --no-cleanup -v

# Cleanup any running services and exit
./scripts/run_benchmark.sh --cleanup-only
```

**Options:**
- `-d, --databases`: Comma-separated databases (postgresql, mysql, sqlite)
- `-s, --scenarios`: Comma-separated scenarios (heavy_inserts, mixed_workload_70_30, etc.)
- `-o, --output`: Custom output directory
- `-v, --verbose`: Enable verbose output
- `-c, --cleanup-only`: Only cleanup services and exit
- `-n, --no-cleanup`: Don't cleanup after benchmark (for debugging)
- `-h, --help`: Show help message

### `cleanup.sh` - Emergency Cleanup

A dedicated script for forceful cleanup of all benchmark services.

**Usage:**
```bash
# Stop all benchmark services
./scripts/cleanup.sh

# Stop services and remove all data volumes
./scripts/cleanup.sh --remove-volumes
```

## Safety Features

### Automatic Cleanup
- **Signal Traps**: Both scripts catch interruption signals (Ctrl+C, SIGTERM) and cleanup automatically
- **Exit Traps**: Services are automatically cleaned up when scripts complete (success or failure)
- **Selective Shutdown**: Only benchmark-related containers are affected, other Docker services remain running

### Error Handling
- **Health Checks**: Scripts wait for all services to be healthy before proceeding
- **Timeout Protection**: 5-minute timeout for service startup
- **Failure Recovery**: Automatic cleanup even if benchmark fails

### Directory Safety
- **Location Validation**: Scripts verify they're run from the correct project directory
- **File Existence Checks**: Verify docker-compose.yml exists before proceeding

## Results Location

Benchmark results are automatically saved to:
```
./results/run_%Y%m%d_%H%M%S/postgresql_heavy_inserts.json
```

The scripts will display:
- 📊 Results file location
- 🚀 Performance summary (if `jq` is available)
- 📉 Performance impact comparison

## 📊 Results Visualization

### `view_results.sh` - Multi-Format Results Viewer

Display and export benchmark results in various formats.

**Usage:**
```bash
# Show latest results in formatted table
./scripts/view_results.sh

# Show specific results file
./scripts/view_results.sh results/run_20250101_120000/postgresql_heavy_inserts.json

# Show only performance comparison
./scripts/view_results.sh -C

# Export to CSV
./scripts/view_results.sh -f csv -o results.csv

# Generate HTML report with interactive charts
./scripts/view_results.sh -f html -c -o report.html

# Export pretty-formatted JSON
./scripts/view_results.sh -f json -o results.json
```

**Supported Formats:**
- `table` - Console table with colors and Unicode box drawing
- `csv` - Comma-separated values for spreadsheet import
- `html` - Styled HTML page with optional interactive charts
- `json` - Pretty-formatted JSON output

### `generate_charts.sh` - Interactive Chart Generation

Create professional interactive HTML charts using Go and go-echarts.

**Prerequisites:**
```bash
# Go 1.21+ (dependencies downloaded automatically)
go version  # Should show 1.21 or higher
```

**Usage:**
```bash
# Generate all chart types as interactive HTML
./scripts/generate_charts.sh

# Generate specific chart type
./scripts/generate_charts.sh -c throughput
./scripts/generate_charts.sh -c dashboard

# Save charts to specific directory
./scripts/generate_charts.sh -c all -o charts/
./scripts/generate_charts.sh -c combined
```

**Chart Types:**
- `throughput` - Operations per second comparison
- `latency` - Latency distribution (P50, P90, P95, P99)
- `combined` - Side-by-side throughput and key latency metrics
- `dashboard` - Comprehensive multi-panel dashboard
- `all` - Generate all chart types (default)

**Features:**
- Interactive HTML charts (hover, zoom, pan)
- Professional styling with themes
- No Python dependencies required
- Automatically builds Go binary on first use

### `demo_visualization.sh` - Visualization Demo

Demonstrates all visualization capabilities using sample data.

```bash
# Run complete demo
./scripts/demo_visualization.sh

# Run demo and clean up afterwards
./scripts/demo_visualization.sh --clean
```

### `generate_report.sh` - Comprehensive Report Generator

Create detailed reports with explanations of benchmarks, methodology, and results interpretation.

**Usage:**
```bash
# Generate comprehensive markdown report
./scripts/generate_report.sh

# Generate HTML report with charts
./scripts/generate_report.sh -f html

# Generate PDF report
./scripts/generate_report.sh -f pdf

# Specify benchmark type and output file
./scripts/generate_report.sh -b postgresql_heavy_inserts -o report.html
```

**What these reports include:**
- 📚 **Complete benchmark explanations** - what each test does and why
- 🎯 **Real-world relevance** - scenarios where this matters
- 📊 **Metrics interpretation** - what the numbers actually mean
- 🔍 **Detailed analysis** - throughput, latency, and consistency impacts
- 💼 **Business impact assessment** - infrastructure and cost implications
- 💡 **Specific recommendations** - what to do based on the results
- 📈 **Interactive HTML charts** - when Go is available

**Supported Formats:**
- `markdown` - Comprehensive markdown with embedded charts
- `html` - Self-contained HTML with styling (uses pandoc if available)
- `pdf` - Professional PDF report (requires wkhtmltopdf)

**Auto-detected Benchmark Types:**
- `postgresql_heavy_inserts` - PostgreSQL INSERT-heavy workload
- `postgresql_mixed_workload` - PostgreSQL mixed read/write workload  
- `mysql_heavy_inserts` - MySQL INSERT-heavy workload
- `sqlite_heavy_inserts` - SQLite INSERT-heavy workload
- `generic` - Generic database benchmark (fallback)

## Example Workflow

```bash
# 1. Run a complete benchmark with cleanup
./scripts/run_benchmark.sh -v

# 2. Or run without cleanup for debugging
./scripts/run_benchmark.sh --no-cleanup -v
# ... debug services ...
./scripts/cleanup.sh  # Manual cleanup when done

# 3. Emergency cleanup if needed
./scripts/cleanup.sh
```

## Dependencies

**Required:**
- Docker & Docker Compose
- Bash (macOS/Linux)

**Optional (for enhanced output):**
- `jq` - For parsing JSON results and showing performance summaries
- `bc` - For calculating performance impact percentages

## Troubleshooting

### Services Won't Start
```bash
# Check service status
docker-compose ps

# View service logs
docker-compose logs [service-name]

# Force cleanup and retry
./scripts/cleanup.sh --remove-volumes
./scripts/run_benchmark.sh
```

### Script Interrupted
If scripts are interrupted, cleanup should happen automatically. If not:
```bash
./scripts/cleanup.sh
```

### Permission Errors
Make sure scripts are executable:
```bash
chmod +x scripts/*.sh
```
