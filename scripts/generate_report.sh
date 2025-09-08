#!/bin/bash

# Comprehensive Benchmark Report Generator
# Explains benchmarks, what they test, why they matter, and interprets results
# Creates detailed, professional reports in markdown, HTML, or PDF

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
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

# Initialize variables
RESULTS_FILE=""
FORMAT="markdown"
OUTPUT_FILE=""
BENCHMARK_NAME=""
INCLUDE_CHARTS=true

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS] [RESULTS_FILE]

Generate a comprehensive benchmark report with explanations of the test, methodology, and results interpretation.

Options:
    -f, --format FORMAT       Output format: markdown, html, pdf (default: markdown)
    -o, --output FILE         Output file (default: nfs_benchmark_report.{md|html|pdf})
    -b, --benchmark NAME      Benchmark name to customize explanations (default: auto-detect)
    -n, --no-charts           Exclude charts from the report
    -h, --help                Show this help message

Arguments:
    RESULTS_FILE              Path to JSON results file (if not provided, finds latest)

Examples:
    $0                                       # Create markdown report for latest results
    $0 -f html -o report.html                # Create HTML report
    $0 results/run_20250908_135000/postgresql_heavy_inserts.json
    $0 -b postgresql_mixed_workload          # Specify benchmark type

Supported formats:
    markdown  - Comprehensive markdown report with embedded images
    html      - Self-contained HTML report with styling and charts
    pdf       - Professional PDF report (requires wkhtmltopdf)

Supported benchmarks:
    postgresql_heavy_inserts    - Heavy INSERT operations in PostgreSQL
    postgresql_mixed_workload   - Mixed read/write PostgreSQL workload
    mysql_heavy_inserts         - Heavy INSERT operations in MySQL
    mysql_mixed_workload        - Mixed read/write MySQL workload
    sqlite_heavy_inserts        - Heavy INSERT operations in SQLite
EOF
}

find_latest_results() {
    local results_dir="$PROJECT_ROOT/results"
    if [ ! -d "$results_dir" ]; then
        print_error "No results directory found at $results_dir"
        exit 1
    fi
    
    local latest_file
    latest_file=$(find "$results_dir" -name "*.json" -type f | sort -r | head -1)
    
    if [ -z "$latest_file" ]; then
        print_error "No JSON results files found in $results_dir"
        exit 1
    fi
    
    echo "$latest_file"
}

detect_benchmark_type() {
    local file="$1"
    
    if ! command -v jq >/dev/null 2>&1; then
        print_warning "jq not found, cannot auto-detect benchmark type."
        echo "generic"
        return
    fi
    
    if jq -e '.metadata.database_type' "$file" >/dev/null 2>&1 && jq -e '.metadata.scenario' "$file" >/dev/null 2>&1; then
        local db_type=$(jq -r '.metadata.database_type' "$file")
        local scenario=$(jq -r '.metadata.scenario' "$file")
        echo "${db_type}_${scenario}"
    else
        local filename=$(basename "$file")
        if [[ "$filename" =~ postgresql_heavy_inserts ]]; then
            echo "postgresql_heavy_inserts"
        elif [[ "$filename" =~ postgresql_mixed ]]; then
            echo "postgresql_mixed_workload"
        elif [[ "$filename" =~ mysql_heavy_inserts ]]; then
            echo "mysql_heavy_inserts"
        elif [[ "$filename" =~ sqlite ]]; then
            echo "sqlite_heavy_inserts"
        else
            echo "generic"
        fi
    fi
}

generate_charts() {
    local file="$1"
    local output_dir="$2"
    
    # Check if Go is available
    if ! command -v go >/dev/null 2>&1; then
        print_warning "Go not found, skipping chart generation."
        print_status "To include charts, install Go: https://golang.org/doc/install"
        return 1
    fi
    
    # Create output directory if it doesn't exist
    mkdir -p "$output_dir"
    
    # Generate charts using Go chart generator
    print_status "Generating charts for report..."
    "$SCRIPT_DIR/generate_charts.sh" -c all -o "$output_dir" "$file"
    
    if [ $? -eq 0 ]; then
        print_success "Charts generated successfully."
        return 0
    else
        print_warning "Chart generation failed."
        return 1
    fi
}

extract_metrics() {
    local file="$1"
    
    if ! command -v jq >/dev/null 2>&1; then
        print_error "jq is required for extracting metrics."
        exit 1
    fi
    
    # Extract key metrics
    local direct_ops=$(jq -r '.direct.Metrics.operations_per_second' "$file")
    local direct_latency=$(jq -r '.direct.Metrics.average_latency / 1000000' "$file")
    local direct_p95=$(jq -r '.direct.Metrics.p95_latency / 1000000' "$file")
    local direct_records=$(jq -r '.direct.DBStats.final_record_count' "$file")
    
    local nfs_ops=$(jq -r '.nfs.Metrics.operations_per_second' "$file")
    local nfs_latency=$(jq -r '.nfs.Metrics.average_latency / 1000000' "$file")
    local nfs_p95=$(jq -r '.nfs.Metrics.p95_latency / 1000000' "$file")
    local nfs_records=$(jq -r '.nfs.DBStats.final_record_count' "$file")
    
    # Calculate overhead percentages
    local throughput_overhead=""
    local latency_overhead=""
    local p95_overhead=""
    
    if command -v bc >/dev/null 2>&1; then
        throughput_overhead=$(echo "scale=1; (($direct_ops - $nfs_ops) / $direct_ops) * 100" | bc -l)
        latency_overhead=$(echo "scale=1; (($nfs_latency - $direct_latency) / $direct_latency) * 100" | bc -l)
        p95_overhead=$(echo "scale=1; (($nfs_p95 - $direct_p95) / $direct_p95) * 100" | bc -l)
    fi
    
    # Return metrics as a JSON object
    cat <<EOF
{
  "direct": {
    "ops": $direct_ops,
    "latency_ms": $direct_latency,
    "p95_ms": $direct_p95,
    "records": $direct_records
  },
  "nfs": {
    "ops": $nfs_ops,
    "latency_ms": $nfs_latency,
    "p95_ms": $nfs_p95,
    "records": $nfs_records
  },
  "overhead": {
    "throughput_pct": $throughput_overhead,
    "latency_pct": $latency_overhead,
    "p95_pct": $p95_overhead
  }
}
EOF
}

get_benchmark_explanation() {
    local benchmark_type="$1"
    
    case "$benchmark_type" in
        postgresql_heavy_inserts)
            cat <<EOF
# PostgreSQL Heavy INSERT Benchmark

## What This Benchmark Tests

This benchmark tests **high-volume data insertion performance** in PostgreSQL when using direct storage versus NFS (Network File System). It performs rapid, concurrent INSERT operations with multiple client threads, designed to stress test storage I/O capabilities.

## Test Methodology

- **Database**: PostgreSQL 14+
- **Operation Type**: INSERT with COPY for bulk data loading
- **Data Pattern**: Fixed-size records with various data types
- **Concurrency**: Multiple worker threads performing parallel insertions
- **Duration**: Timed execution until target operations are reached
- **Storage Options**:
  - **Direct Storage**: Local volumes directly attached to the database
  - **NFS Storage**: Network-mounted filesystem using standard NFS protocol

## Why This Comparison Matters

PostgreSQL's write-ahead logging (WAL) and storage architecture make it particularly sensitive to storage latency. NFS introduces network round-trips and additional protocol overhead that can significantly impact database performance. This benchmark quantifies that overhead.

**Real-world scenarios where this matters**:
- Database servers with network-attached storage
- Cloud environments with shared file systems
- Database migration planning
- Storage system selection for database workloads

## Key Metrics Explained

- **Throughput (ops/sec)**: Number of operations completed per second - higher is better
- **Average Latency**: Typical response time for operations - lower is better
- **P95 Latency**: 95th percentile latency (represents "worst-case" experience) - lower is better
- **Records Processed**: Total number of records successfully inserted during the test

## Interpreting The Results

When analyzing the results, look for:

1. **Throughput Difference**: How much slower is NFS compared to direct storage?
2. **Latency Overhead**: How much additional latency does NFS introduce?
3. **Tail Latencies (P95)**: Does NFS cause more unpredictable performance spikes?
4. **Scaling Pattern**: Does the gap widen as load increases?

In production PostgreSQL deployments, the performance impact shown in this benchmark directly affects database write performance, which cascades to overall application responsiveness.
EOF
            ;;
        postgresql_mixed_workload)
            cat <<EOF
# PostgreSQL Mixed Workload Benchmark

## What This Benchmark Tests

This benchmark simulates a **realistic mix of database operations** that would be found in typical production applications. It executes a combination of reads (SELECT) and writes (INSERT/UPDATE/DELETE) to measure how storage affects overall database performance under varied load.

## Test Methodology

- **Database**: PostgreSQL 14+
- **Operation Mix**: 
  - 70% SELECT operations
  - 20% INSERT operations
  - 10% UPDATE operations
- **Concurrency**: Multiple concurrent client sessions with varied operation types
- **Query Complexity**: Mix of simple point lookups and more complex queries
- **Storage Options**:
  - **Direct Storage**: Local volumes directly attached to the database
  - **NFS Storage**: Network-mounted filesystem using standard NFS protocol

## Why This Comparison Matters

While synthetic benchmarks provide clean measurements, real-world applications rarely perform just one type of database operation. This mixed workload benchmark provides a more realistic picture of how NFS affects database performance in production environments.

**Real-world scenarios where this matters**:
- OLTP (Online Transaction Processing) applications
- Web applications with user interaction
- Business applications with reporting and data entry
- Cloud-hosted databases with various storage options

## Key Metrics Explained

- **Throughput (ops/sec)**: Total operations per second across all operation types
- **Average Latency**: Typical response time across all operations
- **Read Latency**: Response time for SELECT operations specifically
- **Write Latency**: Response time for INSERT/UPDATE operations
- **P95 Latency**: 95th percentile worst-case performance

## Interpreting The Results

When analyzing the results, consider:

1. **Operation Type Impact**: NFS typically affects writes more than reads
2. **Throughput Drop**: Overall performance reduction with NFS
3. **Latency Increase**: Additional response time overhead
4. **Consistency Changes**: Does NFS make performance more unpredictable?

In production environments, the mixed workload results most closely match what users would experience as "database slowness" when NFS is used instead of direct storage.
EOF
            ;;
        mysql_heavy_inserts)
            cat <<EOF
# MySQL Heavy INSERT Benchmark

## What This Benchmark Tests

This benchmark measures **high-volume INSERT performance** in MySQL/MariaDB when using direct storage versus NFS. It focuses on write-intensive operations to highlight the storage subsystem's impact on database write performance.

## Test Methodology

- **Database**: MySQL 8.0+ / MariaDB 10.5+
- **Operation Type**: Bulk INSERT operations with configurable batch sizes
- **Data Characteristics**: Medium-sized records with various column types
- **Concurrency**: Multiple parallel clients inserting data
- **Storage Engine**: InnoDB (the default storage engine)
- **Storage Options**:
  - **Direct Storage**: Local volumes directly attached to the database
  - **NFS Storage**: Network-mounted filesystem using standard NFS protocol

## Why This Comparison Matters

MySQL's InnoDB storage engine has specific I/O patterns for data files and transaction logs. NFS introduces network latency and protocol overhead that can significantly impact these I/O patterns, especially for write operations.

**Real-world scenarios where this matters**:
- High-volume data ingestion systems
- Logging and event storage applications
- ETL (Extract, Transform, Load) processes
- Database servers with network-attached storage

## Key Metrics Explained

- **Throughput (rows/sec)**: Number of rows inserted per second - higher is better
- **Average Latency**: Mean time to complete each operation - lower is better
- **P95 Latency**: 95th percentile worst-case performance - lower is better
- **Total Rows**: Total number of rows successfully inserted

## Interpreting The Results

When analyzing the results, focus on:

1. **Write Amplification**: MySQL/InnoDB often writes data multiple times (data files, logs)
2. **Throughput Reduction**: How much slower data ingestion becomes with NFS
3. **Latency Spikes**: NFS can introduce variable performance under load
4. **Success Rate**: Whether operations complete successfully or time out

For MySQL deployments handling large data volumes, the performance impact shown directly affects database write capacity and application scalability.
EOF
            ;;
        sqlite_heavy_inserts)
            cat <<EOF
# SQLite Heavy INSERT Benchmark

## What This Benchmark Tests

This benchmark evaluates **bulk insertion performance** in SQLite when using direct storage versus NFS. SQLite, being a file-based database, is particularly interesting for storage performance comparisons as it directly interacts with the filesystem.

## Test Methodology

- **Database**: SQLite 3.35+
- **Operation Type**: Bulk INSERT operations
- **Transaction Mode**: Both with and without transactions
- **Synchronization**: Tests with various PRAGMA synchronous settings
- **Storage Options**:
  - **Direct Storage**: Local volumes directly attached to the database
  - **NFS Storage**: Network-mounted filesystem using standard NFS protocol

## Why This Comparison Matters

SQLite is often embedded in applications or used as a local data store. However, in some scenarios (containerized applications, network shares), SQLite databases may operate over NFS. This benchmark quantifies the performance impact of such configurations.

**Real-world scenarios where this matters**:
- Container environments where persistent volumes use NFS
- Application databases on shared network drives
- Portable applications accessing central data stores
- Edge computing with network storage

## Key Metrics Explained

- **Throughput (ops/sec)**: Number of operations completed per second
- **Average Latency**: Mean time for each operation to complete
- **P95 Latency**: 95th percentile latency (representing worst-case performance)
- **Journal Size**: Size of the SQLite journal during operations
- **Database Size**: Final size of the database file

## Interpreting The Results

When analyzing the results, consider:

1. **Transaction Impact**: How transactions affect the NFS performance gap
2. **Sync Settings Effects**: How different synchronization levels change results
3. **Throughput Difference**: Overall performance reduction with NFS
4. **Latency Increase**: Additional operation time with NFS

For applications using SQLite over network storage, these results directly predict performance limitations and potential bottlenecks.
EOF
            ;;
        *)
            cat <<EOF
# NFS vs Direct Storage Benchmark

## What This Benchmark Tests

This benchmark compares database performance when using **direct locally-attached storage** versus **NFS (Network File System)**. It measures the overhead and performance impact introduced by the NFS protocol for database operations.

## Test Methodology

- **Database Operations**: High-throughput read/write operations
- **Concurrency**: Multiple client threads running in parallel
- **Metrics Collection**: Throughput, latency, and resource utilization
- **Storage Options**:
  - **Direct Storage**: Local volumes directly attached to the database
  - **NFS Storage**: Network-mounted filesystem using standard NFS protocol

## Why This Comparison Matters

Databases are highly sensitive to storage performance. While NFS provides flexibility and centralized management, it introduces additional network overhead and protocol layers that can impact performance. This benchmark quantifies that impact to inform storage architecture decisions.

**Real-world scenarios where this matters**:
- Cloud deployments with network-attached storage
- Containerized databases with volume mounts
- High-availability database clusters
- Storage system selection and capacity planning

## Key Metrics Explained

- **Throughput (ops/sec)**: Number of operations completed per second - higher is better
- **Average Latency**: Typical response time for operations - lower is better
- **P95 Latency**: 95th percentile latency (represents "worst-case" experience) - lower is better
- **Total Operations**: Number of operations completed during the test period

## Interpreting The Results

When analyzing the results, focus on:

1. **Throughput Difference**: The percentage decrease in throughput when using NFS
2. **Latency Overhead**: How much additional response time NFS introduces
3. **Consistency Impact**: Whether NFS introduces more performance variability
4. **Operation Type Effects**: Which database operations are most affected

These results help inform storage architecture decisions, capacity planning, and performance expectations for database deployments.
EOF
            ;;
    esac
}

get_results_interpretation() {
    local benchmark_type="$1"
    local metrics="$2"
    
    # Extract key metrics for interpretation
    local direct_ops=$(echo "$metrics" | jq -r '.direct.ops')
    local direct_latency=$(echo "$metrics" | jq -r '.direct.latency_ms')
    local direct_p95=$(echo "$metrics" | jq -r '.direct.p95_ms')
    
    local nfs_ops=$(echo "$metrics" | jq -r '.nfs.ops')
    local nfs_latency=$(echo "$metrics" | jq -r '.nfs.latency_ms')
    local nfs_p95=$(echo "$metrics" | jq -r '.nfs.p95_ms')
    
    local throughput_overhead=$(echo "$metrics" | jq -r '.overhead.throughput_pct')
    local latency_overhead=$(echo "$metrics" | jq -r '.overhead.latency_pct')
    local p95_overhead=$(echo "$metrics" | jq -r '.overhead.p95_pct')

    # Determine severity levels
    local throughput_severity="moderate"
    if (( $(echo "$throughput_overhead > 50" | bc -l) )); then
        throughput_severity="significant"
    fi
    if (( $(echo "$throughput_overhead > 80" | bc -l) )); then
        throughput_severity="severe"
    fi
    
    local latency_severity="moderate"
    if (( $(echo "$latency_overhead > 100" | bc -l) )); then
        latency_severity="significant"
    fi
    if (( $(echo "$latency_overhead > 200" | bc -l) )); then
        latency_severity="severe"
    fi
    
    # Calculate specific type of interpretation
    case "$benchmark_type" in
        postgresql_heavy_inserts|mysql_heavy_inserts)
            cat <<EOF
## Results Interpretation

### Summary of Findings

The benchmark results demonstrate a **${throughput_severity} performance impact** when using NFS storage for database write operations:

- **Throughput Reduction**: ${throughput_overhead}% lower throughput with NFS storage
- **Latency Increase**: ${latency_overhead}% higher average response time
- **Tail Latency Impact**: ${p95_overhead}% higher P95 (worst-case) latency

### Analysis

1. **Write Performance Impact**

   Direct storage achieved **${direct_ops} operations/second** compared to **${nfs_ops} operations/second** with NFS. This ${throughput_overhead}% reduction in throughput is primarily caused by:
   
   - Network round-trip latency for each filesystem operation
   - NFS protocol overhead for write synchronization
   - Potential network congestion and packet retransmissions
   - Additional system calls and context switches

2. **Latency Implications**

   Average operation latency increased from **${direct_latency}ms** with direct storage to **${nfs_latency}ms** with NFS. This ${latency_overhead}% increase means:
   
   - Each database operation takes longer to complete
   - Client applications experience slower response times
   - Connection pools require more connections for the same throughput
   - Database timeouts may occur more frequently under load

3. **Consistency and Predictability**

   The P95 latency (representing worst-case performance) increased from **${direct_p95}ms** to **${nfs_p95}ms** - a ${p95_overhead}% increase. This indicates:
   
   - More variable performance with NFS
   - Higher likelihood of timeout errors during peak loads
   - Less predictable application response times
   - Potential for cascading performance issues under stress

### Business Impact

For **write-intensive database workloads**, this benchmark demonstrates that NFS introduces a substantial performance penalty. In production environments, this would translate to:

- Increased infrastructure costs (needing more powerful systems to achieve the same throughput)
- Reduced application responsiveness
- Lower maximum throughput capacity
- More frequent performance-related incidents

### Recommendations

Based on these results:

1. **For write-intensive workloads**: Strongly prefer direct-attached storage over NFS when possible
2. **If NFS must be used**:
   - Increase connection timeouts to accommodate higher latency
   - Consider read replicas with direct storage for read-heavy operations
   - Implement aggressive connection pooling and retry mechanisms
   - Tune NFS mount options for database workloads
   - Consider async I/O where consistency requirements permit
3. **Monitoring considerations**:
   - Set alert thresholds ${latency_overhead}% higher for NFS-based storage
   - Budget for ${throughput_overhead}% lower maximum throughput capacity
EOF
            ;;
        postgresql_mixed_workload)
            cat <<EOF
## Results Interpretation

### Summary of Findings

The mixed workload benchmark shows a **${throughput_severity} overall performance impact** when using NFS for PostgreSQL:

- **Overall Throughput**: ${throughput_overhead}% lower with NFS storage
- **Average Latency**: ${latency_overhead}% higher with NFS storage
- **Worst-case Latency**: ${p95_overhead}% higher P95 latency with NFS

### Analysis

1. **Operation Type Impact**

   With mixed read/write operations, the overall throughput decreased from **${direct_ops} ops/second** to **${nfs_ops} ops/second**. This ${throughput_overhead}% reduction varies by operation type:
   
   - Write operations (INSERT/UPDATE) typically see a larger impact
   - Read operations (SELECT) are less affected but still show performance degradation
   - Transaction commit operations experience significant latency increases
   
   This suggests that application workloads with higher write percentages will experience greater performance penalties with NFS.

2. **Response Time Considerations**

   Average response time increased from **${direct_latency}ms** to **${nfs_latency}ms**, a ${latency_overhead}% increase. For application workloads, this means:
   
   - User-facing operations feel noticeably slower
   - API response times increase
   - Background processing takes longer
   - Database connection time increases

3. **Predictability and Consistency**

   The P95 latency increased from **${direct_p95}ms** to **${nfs_p95}ms** (${p95_overhead}% higher). This significant increase in tail latency indicates:
   
   - More unpredictable performance with NFS
   - Higher likelihood of timeout errors
   - Increased frequency of slow queries
   - More variable user experience

### Business Impact

For **typical application workloads** with mixed read/write operations, these results indicate:

- Reduced application responsiveness and user satisfaction
- Lower maximum concurrent user capacity
- Increased infrastructure costs to maintain the same performance level
- Higher likelihood of timeout errors and related application issues

### Recommendations

Based on these results:

1. **For typical application databases**:
   - Prefer direct-attached storage where possible
   - Consider separating read and write workloads (read replicas on NFS, primary on direct storage)
   - Increase connection timeouts by at least ${latency_overhead}%
   - Plan for ${throughput_overhead}% lower system capacity with NFS

2. **NFS Optimization** (if NFS must be used):
   - Tune NFS mount options for database workloads (rsize, wsize, async)
   - Increase PostgreSQL's maintenance_work_mem for better NFS performance
   - Consider larger shared_buffers to reduce storage I/O
   - Use connection pooling to reduce the impact of higher latency
   
3. **Application Considerations**:
   - Implement more aggressive caching strategies
   - Consider batch processing for write operations
   - Extend timeout settings proportional to latency increases
EOF
            ;;
        sqlite_heavy_inserts)
            cat <<EOF
## Results Interpretation

### Summary of Findings

This SQLite benchmark shows a **${throughput_severity} performance impact** when using NFS storage instead of direct storage:

- **Throughput Reduction**: ${throughput_overhead}% lower throughput with NFS
- **Latency Increase**: ${latency_overhead}% higher average latency
- **Worst-case Performance**: ${p95_overhead}% higher P95 latency

### Analysis

1. **SQLite's Unique Characteristics**

   SQLite achieved **${direct_ops} operations/second** with direct storage versus **${nfs_ops} operations/second** with NFS. This ${throughput_overhead}% reduction is particularly notable because:
   
   - SQLite operates directly on files without a server process
   - Journal operations require additional file operations
   - File locking is heavily affected by NFS latency
   - Synchronization operations are particularly expensive over NFS

2. **Response Time Impact**

   Average operation latency increased from **${direct_latency}ms** to **${nfs_latency}ms** (${latency_overhead}% higher). For SQLite-based applications, this means:
   
   - Each transaction takes longer to complete
   - Database contention increases with concurrent operations
   - Lock wait times increase significantly
   - File operation overhead becomes dominant

3. **Consistency Concerns**

   The P95 latency increased from **${direct_p95}ms** to **${nfs_p95}ms** (${p95_overhead}% higher). This substantial increase in worst-case performance indicates:
   
   - Occasional significant delays in database operations
   - Higher likelihood of "Database is locked" errors
   - More timeout errors under concurrent access
   - Less predictable application behavior

### Business Impact

For **applications using SQLite over NFS**, these results predict:

- Significantly reduced application performance
- Higher rates of database lock errors
- Reduced concurrency capacity
- Potential data integrity issues if timeouts are not handled properly

### Recommendations

Based on these results:

1. **For SQLite deployments**:
   - Strongly avoid NFS for SQLite databases when possible
   - If NFS must be used, consider WAL journal mode to reduce locking
   - Reduce SQLite's synchronous setting (with appropriate data safety considerations)
   - Implement aggressive timeout handling and retry logic

2. **Alternative Approaches**:
   - Consider using a client-server database (PostgreSQL, MySQL) instead of SQLite for network storage
   - Implement application-level caching to reduce database operations
   - Use SQLite as a local cache with periodic synchronization to a primary datastore
   - Consider SQLite's in-memory mode with periodic persistence for appropriate workloads
EOF
            ;;
        *)
            cat <<EOF
## Results Interpretation

### Summary of Findings

The benchmark results reveal a **${throughput_severity} performance impact** when using NFS storage instead of direct storage for database operations:

- **Throughput Reduction**: ${throughput_overhead}% lower with NFS storage
- **Latency Increase**: ${latency_overhead}% higher average response time
- **Worst-case Performance**: ${p95_overhead}% higher P95 latency

### Analysis

1. **Performance Overhead**

   Direct storage achieved **${direct_ops} operations/second** compared to **${nfs_ops} operations/second** with NFS storage. This ${throughput_overhead}% reduction in throughput is caused by:
   
   - Network round-trip time for each I/O operation
   - NFS protocol overhead (especially for synchronous operations)
   - Additional filesystem layers and caching mechanisms
   - Potential network congestion and retransmissions

2. **Response Time Impact**

   Average operation latency increased from **${direct_latency}ms** with direct storage to **${nfs_latency}ms** with NFS. This ${latency_overhead}% increase means:
   
   - Each database operation takes longer to complete
   - Applications experience slower response times
   - Transactions hold locks longer, increasing contention
   - System throughput decreases accordingly

3. **Predictability Concerns**

   The P95 latency (representing worst-case performance) increased from **${direct_p95}ms** to **${nfs_p95}ms** - a ${p95_overhead}% increase. This indicates:
   
   - More variable performance with NFS
   - Higher likelihood of timeout errors
   - Less predictable application behavior
   - Potential cascading performance issues under load

### Business Impact

For **database workloads**, these results indicate that NFS introduces a substantial performance penalty that would translate to:

- Higher infrastructure costs to achieve the same performance
- Reduced application responsiveness
- Lower maximum throughput capacity
- More frequent performance-related incidents

### Recommendations

Based on these results:

1. **Storage Selection**:
   - Prefer direct-attached storage for database workloads when possible
   - Consider the ${throughput_overhead}% performance cost when evaluating NFS for databases
   
2. **If NFS must be used**:
   - Plan for ${throughput_overhead}% lower throughput capacity
   - Increase application timeouts to accommodate ${latency_overhead}% higher latency
   - Implement more aggressive connection pooling
   - Consider read replicas with direct storage for read-heavy workloads
   
3. **NFS Optimization**:
   - Tune NFS mount options (rsize, wsize, async where appropriate)
   - Use high-performance NFS implementations
   - Ensure low-latency network connectivity between database and NFS server
   - Consider NFS caching mechanisms where appropriate
EOF
            ;;
    esac
}

generate_markdown_report() {
    local file="$1"
    local benchmark_type="$2"
    local metrics="$3"
    local output_file="$4"
    local charts_dir="$5"
    
    # Get benchmark explanation and results interpretation
    local benchmark_explanation=$(get_benchmark_explanation "$benchmark_type")
    local results_interpretation=$(get_results_interpretation "$benchmark_type" "$metrics")
    
    # Get report date
    local report_date=$(date +"%B %d, %Y")
    
    # Create markdown report
    cat > "$output_file" << EOF
# NFS vs Direct Storage Benchmark Report
**Generated on $report_date**

$benchmark_explanation

## Benchmark Results

### Key Performance Metrics

| Metric | Direct Storage | NFS Storage | Difference |
|--------|---------------|------------|------------|
| Throughput | $(echo "$metrics" | jq -r '.direct.ops') ops/sec | $(echo "$metrics" | jq -r '.nfs.ops') ops/sec | $(echo "$metrics" | jq -r '.overhead.throughput_pct')% slower |
| Average Latency | $(echo "$metrics" | jq -r '.direct.latency_ms') ms | $(echo "$metrics" | jq -r '.nfs.latency_ms') ms | $(echo "$metrics" | jq -r '.overhead.latency_pct')% higher |
| P95 Latency | $(echo "$metrics" | jq -r '.direct.p95_ms') ms | $(echo "$metrics" | jq -r '.nfs.p95_ms') ms | $(echo "$metrics" | jq -r '.overhead.p95_pct')% higher |
| Records Processed | $(echo "$metrics" | jq -r '.direct.records') | $(echo "$metrics" | jq -r '.nfs.records') | - |

EOF

    # Add charts if available
    if [ "$INCLUDE_CHARTS" = true ] && [ -d "$charts_dir" ]; then
        cat >> "$output_file" << EOF
### Performance Visualizations

#### Throughput Comparison
![Throughput Comparison]($(find "$charts_dir" -name "*throughput*" | head -1 | sed 's|^|./|'))

#### Latency Distribution
![Latency Distribution]($(find "$charts_dir" -name "*latency*" | head -1 | sed 's|^|./|'))

#### Overall Performance Dashboard
![Performance Dashboard]($(find "$charts_dir" -name "*dashboard*" | head -1 | sed 's|^|./|'))

EOF
    fi

    # Add results interpretation
    cat >> "$output_file" << EOF
$results_interpretation

## Conclusion

This benchmark clearly demonstrates the performance trade-offs between direct storage and NFS for database operations. While NFS provides flexibility, centralized management, and potential cost benefits, it introduces a significant performance overhead for database workloads.

Organizations should carefully weigh these performance implications against the operational benefits of NFS when designing database storage architectures. When maximum performance is critical, direct storage should be preferred.

---

*This report was automatically generated from benchmark results. For more information about the benchmark methodology and tools, please refer to the project documentation.*
EOF

    print_success "Markdown report generated: $output_file"
}

generate_html_report() {
    local file="$1"
    local benchmark_type="$2"
    local metrics="$3"
    local output_file="$4"
    local charts_dir="$5"
    
    # Create temporary markdown file
    local temp_md=$(mktemp)
    generate_markdown_report "$file" "$benchmark_type" "$metrics" "$temp_md" "$charts_dir"
    
    # Check if pandoc is available for conversion
    if command -v pandoc >/dev/null 2>&1; then
        # Use pandoc to convert markdown to HTML with styling
        pandoc -s -c https://cdn.jsdelivr.net/npm/water.css@2/out/water.css --metadata title="NFS vs Direct Storage Benchmark Report" "$temp_md" -o "$output_file"
        rm "$temp_md"
        print_success "HTML report generated using pandoc: $output_file"
    else
        # Manual HTML conversion (basic)
        print_warning "pandoc not found, creating basic HTML report."
        print_status "For better HTML reports, install pandoc: brew install pandoc"
        
        # Get benchmark explanation and results interpretation
        local benchmark_explanation=$(get_benchmark_explanation "$benchmark_type")
        local results_interpretation=$(get_results_interpretation "$benchmark_type" "$metrics")
        
        # Replace markdown headers with HTML headers
        benchmark_explanation=$(echo "$benchmark_explanation" | sed 's/^# /\<h1\>/g' | sed 's/^## /\<h2\>/g' | sed 's/^### /\<h3\>/g')
        results_interpretation=$(echo "$results_interpretation" | sed 's/^# /\<h1\>/g' | sed 's/^## /\<h2\>/g' | sed 's/^### /\<h3\>/g')
        
        # Replace markdown lists with HTML lists
        benchmark_explanation=$(echo "$benchmark_explanation" | sed 's/^- /\<li\>/g' | sed 's/$/<\/li>/g')
        results_interpretation=$(echo "$results_interpretation" | sed 's/^- /\<li\>/g' | sed 's/$/<\/li>/g')
        
        # Get report date
        local report_date=$(date +"%B %d, %Y")
        
        # Create HTML report
        cat > "$output_file" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>NFS vs Direct Storage Benchmark Report</title>
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/water.css@2/out/water.css">
    <style>
        body {
            max-width: 1200px;
            margin: 0 auto;
            padding: 20px;
            line-height: 1.6;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin: 20px 0;
        }
        th, td {
            padding: 10px;
            border: 1px solid #ddd;
            text-align: left;
        }
        th {
            background-color: #f5f5f5;
        }
        img {
            max-width: 100%;
            height: auto;
            margin: 20px 0;
            border: 1px solid #ddd;
        }
        .chart-container {
            margin: 30px 0;
        }
        .highlight {
            background-color: #ffffd0;
            padding: 2px 4px;
            border-radius: 3px;
        }
    </style>
</head>
<body>
    <h1>NFS vs Direct Storage Benchmark Report</h1>
    <p><em>Generated on $report_date</em></p>
    
    $benchmark_explanation
    
    <h2>Benchmark Results</h2>
    
    <h3>Key Performance Metrics</h3>
    
    <table>
        <tr>
            <th>Metric</th>
            <th>Direct Storage</th>
            <th>NFS Storage</th>
            <th>Difference</th>
        </tr>
        <tr>
            <td>Throughput</td>
            <td>$(echo "$metrics" | jq -r '.direct.ops') ops/sec</td>
            <td>$(echo "$metrics" | jq -r '.nfs.ops') ops/sec</td>
            <td><span class="highlight">$(echo "$metrics" | jq -r '.overhead.throughput_pct')% slower</span></td>
        </tr>
        <tr>
            <td>Average Latency</td>
            <td>$(echo "$metrics" | jq -r '.direct.latency_ms') ms</td>
            <td>$(echo "$metrics" | jq -r '.nfs.latency_ms') ms</td>
            <td><span class="highlight">$(echo "$metrics" | jq -r '.overhead.latency_pct')% higher</span></td>
        </tr>
        <tr>
            <td>P95 Latency</td>
            <td>$(echo "$metrics" | jq -r '.direct.p95_ms') ms</td>
            <td>$(echo "$metrics" | jq -r '.nfs.p95_ms') ms</td>
            <td><span class="highlight">$(echo "$metrics" | jq -r '.overhead.p95_pct')% higher</span></td>
        </tr>
        <tr>
            <td>Records Processed</td>
            <td>$(echo "$metrics" | jq -r '.direct.records')</td>
            <td>$(echo "$metrics" | jq -r '.nfs.records')</td>
            <td>-</td>
        </tr>
    </table>
EOF

        # Add charts if available
        if [ "$INCLUDE_CHARTS" = true ] && [ -d "$charts_dir" ]; then
            # Find chart files
            local throughput_chart=$(find "$charts_dir" -name "*throughput*" | head -1)
            local latency_chart=$(find "$charts_dir" -name "*latency*" | head -1)
            local dashboard_chart=$(find "$charts_dir" -name "*dashboard*" | head -1)
            
            # Add chart section if any charts were found
            if [ -n "$throughput_chart" ] || [ -n "$latency_chart" ] || [ -n "$dashboard_chart" ]; then
                cat >> "$output_file" << EOF
    <h3>Performance Visualizations</h3>
EOF
                
                if [ -n "$throughput_chart" ]; then
                    cat >> "$output_file" << EOF
    <div class="chart-container">
        <h4>Throughput Comparison</h4>
        <img src="$(echo "$throughput_chart" | sed 's|^|./|')" alt="Throughput Comparison">
    </div>
EOF
                fi
                
                if [ -n "$latency_chart" ]; then
                    cat >> "$output_file" << EOF
    <div class="chart-container">
        <h4>Latency Distribution</h4>
        <img src="$(echo "$latency_chart" | sed 's|^|./|')" alt="Latency Distribution">
    </div>
EOF
                fi
                
                if [ -n "$dashboard_chart" ]; then
                    cat >> "$output_file" << EOF
    <div class="chart-container">
        <h4>Overall Performance Dashboard</h4>
        <img src="$(echo "$dashboard_chart" | sed 's|^|./|')" alt="Performance Dashboard">
    </div>
EOF
                fi
            fi
        fi

        # Add results interpretation and conclusion
        cat >> "$output_file" << EOF
    
    $results_interpretation
    
    <h2>Conclusion</h2>
    
    <p>This benchmark clearly demonstrates the performance trade-offs between direct storage and NFS for database operations. While NFS provides flexibility, centralized management, and potential cost benefits, it introduces a significant performance overhead for database workloads.</p>
    
    <p>Organizations should carefully weigh these performance implications against the operational benefits of NFS when designing database storage architectures. When maximum performance is critical, direct storage should be preferred.</p>
    
    <hr>
    
    <p><em>This report was automatically generated from benchmark results. For more information about the benchmark methodology and tools, please refer to the project documentation.</em></p>
</body>
</html>
EOF
        
        print_success "Basic HTML report generated: $output_file"
    fi
}

generate_pdf_report() {
    local file="$1"
    local benchmark_type="$2"
    local metrics="$3"
    local output_file="$4"
    local charts_dir="$5"
    
    # Check if wkhtmltopdf is available
    if ! command -v wkhtmltopdf >/dev/null 2>&1; then
        print_error "wkhtmltopdf is required for PDF generation but not found."
        print_status "Install with: brew install wkhtmltopdf"
        exit 1
    fi
    
    # Create temporary HTML file
    local temp_html=$(mktemp).html
    generate_html_report "$file" "$benchmark_type" "$metrics" "$temp_html" "$charts_dir"
    
    # Convert HTML to PDF
    wkhtmltopdf "$temp_html" "$output_file"
    
    # Clean up temporary file
    rm "$temp_html"
    
    print_success "PDF report generated: $output_file"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--format)
            FORMAT="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -b|--benchmark)
            BENCHMARK_NAME="$2"
            shift 2
            ;;
        -n|--no-charts)
            INCLUDE_CHARTS=false
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        -*)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
        *)
            RESULTS_FILE="$1"
            shift
            ;;
    esac
done

main() {
    # Find results file if not specified
    if [ -z "$RESULTS_FILE" ]; then
        RESULTS_FILE=$(find_latest_results)
        print_status "Using latest results file: $RESULTS_FILE"
    elif [ ! -f "$RESULTS_FILE" ]; then
        print_error "Results file not found: $RESULTS_FILE"
        exit 1
    fi
    
    # Create output directory
    local output_dir=$(dirname "$RESULTS_FILE")
    if [ -z "$OUTPUT_FILE" ]; then
        case "$FORMAT" in
            markdown)
                OUTPUT_FILE="$output_dir/nfs_benchmark_report.md"
                ;;
            html)
                OUTPUT_FILE="$output_dir/nfs_benchmark_report.html"
                ;;
            pdf)
                OUTPUT_FILE="$output_dir/nfs_benchmark_report.pdf"
                ;;
            *)
                print_error "Unsupported format: $FORMAT"
                show_usage
                exit 1
                ;;
        esac
    fi
    
    # Detect benchmark type if not specified
    if [ -z "$BENCHMARK_NAME" ]; then
        BENCHMARK_NAME=$(detect_benchmark_type "$RESULTS_FILE")
        print_status "Detected benchmark type: $BENCHMARK_NAME"
    fi
    
    # Generate charts if requested
    local charts_dir=""
    if [ "$INCLUDE_CHARTS" = true ]; then
        charts_dir="$output_dir/charts"
        generate_charts "$RESULTS_FILE" "$charts_dir"
    fi
    
    # Extract metrics
    print_status "Extracting performance metrics..."
    local metrics=$(extract_metrics "$RESULTS_FILE")
    
    # Generate report in requested format
    print_status "Generating $FORMAT report..."
    case "$FORMAT" in
        markdown)
            generate_markdown_report "$RESULTS_FILE" "$BENCHMARK_NAME" "$metrics" "$OUTPUT_FILE" "$charts_dir"
            ;;
        html)
            generate_html_report "$RESULTS_FILE" "$BENCHMARK_NAME" "$metrics" "$OUTPUT_FILE" "$charts_dir"
            ;;
        pdf)
            generate_pdf_report "$RESULTS_FILE" "$BENCHMARK_NAME" "$metrics" "$OUTPUT_FILE" "$charts_dir"
            ;;
    esac
    
    print_success "Report generation complete: $OUTPUT_FILE"
}

main
