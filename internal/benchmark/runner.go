package benchmark

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strconv"
	"sync"
	"time"

	"github.com/l22io/nfsvsdirectbench/internal/config"
	"github.com/l22io/nfsvsdirectbench/internal/database"
	"github.com/l22io/nfsvsdirectbench/internal/metrics"
)

// Results contains benchmark execution results
type Results struct {
	OutputDir     string
	TotalDuration time.Duration
	ScenarioResults map[string]*ScenarioResult
	StartTime     time.Time
	EndTime       time.Time
}

// ScenarioResult contains results for a single scenario
type ScenarioResult struct {
	Name        string
	Database    string
	StorageType string
	Duration    time.Duration
	Success     bool
	Error       error
	Metrics     *metrics.Results
	DBStats     map[string]interface{}
}

// Runner orchestrates benchmark execution
type Runner struct {
	config *config.Config
}

// NewRunner creates a new benchmark runner
func NewRunner(cfg *config.Config) *Runner {
	return &Runner{
		config: cfg,
	}
}

// RunAll executes the complete benchmark suite
func (r *Runner) RunAll(ctx context.Context) (*Results, error) {
	startTime := time.Now()
	
	// Create output directory
	outputDir, err := r.createOutputDir()
	if err != nil {
		return nil, fmt.Errorf("failed to create output directory: %w", err)
	}
	
	log.Printf("Starting benchmark suite - output: %s", outputDir)
	
	results := &Results{
		OutputDir:       outputDir,
		ScenarioResults: make(map[string]*ScenarioResult),
		StartTime:       startTime,
	}
	
	// Get enabled databases and scenarios
	databases := r.config.GetEnabledDatabases()
	scenarios := r.config.GetEnabledScenarios()
	
	log.Printf("Running %d scenarios against %d databases", len(scenarios), len(databases))
	
	// Execute each scenario against each database
	for _, db := range databases {
		for _, scenario := range scenarios {
			if err := r.runScenario(ctx, db, scenario, results); err != nil {
				if r.config.Execution.FailFast {
					return nil, fmt.Errorf("scenario %s failed on %s: %w", scenario.Name, db, err)
				}
				log.Printf("Scenario %s failed on %s: %v (continuing)", scenario.Name, db, err)
			}
		}
	}
	
	results.EndTime = time.Now()
	results.TotalDuration = results.EndTime.Sub(results.StartTime)
	
	return results, nil
}

func (r *Runner) createOutputDir() (string, error) {
	timestamp := time.Now().Format(r.config.Global.TimestampFormat)
	outputDir := filepath.Join(r.config.Global.OutputDir, fmt.Sprintf("run_%s", timestamp))
	
	// Create the directory
	if err := os.MkdirAll(outputDir, 0755); err != nil {
		return "", fmt.Errorf("failed to create output directory: %w", err)
	}
	
	return outputDir, nil
}

func (r *Runner) runScenario(ctx context.Context, database string, scenario config.ScenarioConfig, results *Results) error {
	log.Printf("Running scenario '%s' on database '%s'", scenario.Name, database)
	
	scenarioStart := time.Now()
	
	// Only implement PostgreSQL for now
	if database != "postgresql" {
		log.Printf("Skipping %s - only PostgreSQL implemented", database)
		return nil
	}

	// Only implement heavy_inserts for now
	if scenario.Name != "heavy_inserts" {
		log.Printf("Skipping scenario %s - only heavy_inserts implemented", scenario.Name)
		return nil
	}

	// Run benchmark on direct storage
	directResult, err := r.runPostgreSQLHeavyInserts(ctx, "direct", scenario)
	if err != nil {
		log.Printf("Direct storage benchmark failed: %v", err)
		directResult = &ScenarioResult{
			Name:        scenario.Name,
			Database:    database,
			StorageType: "direct",
			Success:     false,
			Error:       err,
		}
	}

	// Run benchmark on NFS storage
	nfsResult, err := r.runPostgreSQLHeavyInserts(ctx, "nfs", scenario)
	if err != nil {
		log.Printf("NFS storage benchmark failed: %v", err)
		nfsResult = &ScenarioResult{
			Name:        scenario.Name,
			Database:    database,
			StorageType: "nfs",
			Success:     false,
			Error:       err,
		}
	}

	// Store results
	directKey := fmt.Sprintf("%s_%s_direct", database, scenario.Name)
	nfsKey := fmt.Sprintf("%s_%s_nfs", database, scenario.Name)
	results.ScenarioResults[directKey] = directResult
	results.ScenarioResults[nfsKey] = nfsResult

	// Save results to JSON file
	if err := r.saveScenarioResults(results.OutputDir, directResult, nfsResult); err != nil {
		log.Printf("Failed to save results: %v", err)
	}

	scenarioDuration := time.Since(scenarioStart)
	log.Printf("Completed scenario '%s' on '%s' in %v", scenario.Name, database, scenarioDuration)

	return nil
}

func (r *Runner) runPostgreSQLHeavyInserts(ctx context.Context, storageType string, scenario config.ScenarioConfig) (*ScenarioResult, error) {
	// Get database config
	var dbConfig config.DatabaseConnectionConfig
	postgresConfig := r.config.Databases["postgresql"]
	if storageType == "direct" {
		dbConfig = postgresConfig.Direct
	} else {
		dbConfig = postgresConfig.NFS
	}

	// Connect to database
	db, err := database.NewPostgresDB(dbConfig, fmt.Sprintf("postgresql-%s", storageType))
	if err != nil {
		return nil, fmt.Errorf("failed to connect to database: %w", err)
	}
	defer db.Close()

	// Setup benchmark table
	if err := db.CreateBenchmarkTable(); err != nil {
		return nil, fmt.Errorf("failed to create benchmark table: %w", err)
	}

	if err := db.ClearBenchmarkTable(); err != nil {
		return nil, fmt.Errorf("failed to clear benchmark table: %w", err)
	}

	// Get scenario parameters
	threads, _ := strconv.Atoi(fmt.Sprintf("%v", scenario.Parameters["threads"]))
	batchSize, _ := strconv.Atoi(fmt.Sprintf("%v", scenario.Parameters["batch_size"]))
	recordSizeStr := fmt.Sprintf("%v", scenario.Parameters["record_size"])
	recordSize := database.RecordSize(recordSizeStr)

	log.Printf("Starting %s benchmark: %d threads, %d batch size, %s records for %ds", 
		storageType, threads, batchSize, recordSize, scenario.Duration)

	// Create metrics collector
	collector := metrics.NewCollector()
	collector.Start()

	// Run workload for specified duration
	var wg sync.WaitGroup
	ctx, cancel := context.WithTimeout(ctx, time.Duration(scenario.Duration)*time.Second)
	defer cancel()

	var totalInserted int64
	var mu sync.Mutex

	for i := 0; i < threads; i++ {
		wg.Add(1)
		go func(threadID int) {
			defer wg.Done()
			threadInserted := r.runInsertThread(ctx, db, batchSize, recordSize, collector)
			mu.Lock()
			totalInserted += threadInserted
			mu.Unlock()
		}(i)
	}

	wg.Wait()
	collector.End()
	collector.SetThroughput(totalInserted)

	// Get final database stats
	dbStats, err := db.GetStats()
	if err != nil {
		log.Printf("Failed to get database stats: %v", err)
		dbStats = make(map[string]interface{})
	}

	// Get final record count
	recordCount, err := db.CountRecords()
	if err != nil {
		log.Printf("Failed to count records: %v", err)
	}
	dbStats["final_record_count"] = recordCount

	results := collector.Results()
	log.Printf("%s results: %d ops in %v (%.2f ops/sec), avg latency: %v, p95: %v", 
		storageType, results.TotalOperations, results.TotalDuration, 
		results.OperationsPerSecond, results.AverageLatency, results.P95Latency)

	return &ScenarioResult{
		Name:        scenario.Name,
		Database:    "postgresql",
		StorageType: storageType,
		Duration:    results.TotalDuration,
		Success:     true,
		Metrics:     results,
		DBStats:     dbStats,
	}, nil
}

func (r *Runner) runInsertThread(ctx context.Context, db database.Database, batchSize int, recordSize database.RecordSize, collector *metrics.Collector) int64 {
	var inserted int64

	for {
		select {
		case <-ctx.Done():
			return inserted
		default:
			// Generate batch of records
			batch := database.GenerateBenchmarkRecords(batchSize, recordSize)

			// Measure insert latency
			start := time.Now()
			err := db.InsertBatch(batch)
			latency := time.Since(start)

			if err != nil {
				collector.AddError(err)
				time.Sleep(time.Millisecond * 100) // Brief pause on error
				continue
			}

			collector.AddLatency(latency)
			inserted += int64(batchSize)
		}
	}
}

func (r *Runner) saveScenarioResults(outputDir string, directResult, nfsResult *ScenarioResult) error {
	results := map[string]*ScenarioResult{
		"direct": directResult,
		"nfs":    nfsResult,
	}

	filePath := filepath.Join(outputDir, "postgresql_heavy_inserts.json")
	file, err := os.Create(filePath)
	if err != nil {
		return err
	}
	defer file.Close()

	encoder := json.NewEncoder(file)
	encoder.SetIndent("", "  ")
	return encoder.Encode(results)
}

// GetOverheadPercent calculates the performance overhead of NFS vs direct storage
func GetOverheadPercent(directMetric, nfsMetric float64) float64 {
	if directMetric == 0 {
		return 0
	}
	return ((nfsMetric - directMetric) / directMetric) * 100
}
