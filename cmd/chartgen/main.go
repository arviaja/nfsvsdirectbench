package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io/fs"
	"log"
	"math"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/go-echarts/go-echarts/v2/charts"
	"github.com/go-echarts/go-echarts/v2/components"
	"github.com/go-echarts/go-echarts/v2/opts"
	"github.com/go-echarts/go-echarts/v2/types"
)

type BenchmarkResults struct {
	Metadata struct {
		Timestamp    string `json:"timestamp"`
		DatabaseType string `json:"database_type"`
		Scenario     string `json:"scenario"`
		Version      string `json:"version"`
	} `json:"metadata"`
	Direct DirectResults `json:"direct"`
	NFS    NFSResults    `json:"nfs"`
}

type DirectResults struct {
	Duration int64       `json:"Duration"`
	Metrics  Metrics     `json:"Metrics"`
	DBStats  DatabaseStats `json:"DBStats"`
}

type NFSResults struct {
	Duration int64       `json:"Duration"`
	Metrics  Metrics     `json:"Metrics"`
	DBStats  DatabaseStats `json:"DBStats"`
}

type Metrics struct {
	TotalOperations    int64   `json:"total_operations"`
	OperationsPerSecond float64 `json:"operations_per_second"`
	AverageLatency     int64   `json:"average_latency"`
	MinLatency         int64   `json:"min_latency"`
	MaxLatency         int64   `json:"max_latency"`
	P50Latency         int64   `json:"p50_latency"`
	P90Latency         int64   `json:"p90_latency"`
	P95Latency         int64   `json:"p95_latency"`
	P99Latency         int64   `json:"p99_latency"`
}

type DatabaseStats struct {
	FinalRecordCount int64 `json:"final_record_count"`
	TableSizeBytes   int64 `json:"table_size_bytes"`
	IndexSizeBytes   int64 `json:"index_size_bytes"`
}

type ChartGenerator struct {
	results BenchmarkResults
	outputDir string
}

func main() {
	var (
		inputFile = flag.String("input", "", "Path to JSON results file (required)")
		outputDir = flag.String("output", "", "Output directory for charts (default: same as input file)")
		chartType = flag.String("chart", "all", "Chart type: throughput, latency, combined, dashboard, all")
		help      = flag.Bool("help", false, "Show help message")
	)
	flag.Parse()

	if *help {
		showUsage()
		return
	}

	if *inputFile == "" {
		// Try to find latest results file
		latest, err := findLatestResults()
		if err != nil {
		log.Fatalf("[ERROR] No input file specified and couldn't find latest results: %v", err)
		}
		*inputFile = latest
		fmt.Printf("[INFO] Using latest results: %s\n", *inputFile)
	}

	if *outputDir == "" {
		*outputDir = filepath.Dir(*inputFile)
	}

	generator, err := NewChartGenerator(*inputFile, *outputDir)
	if err != nil {
		log.Fatalf("[ERROR] Failed to initialize chart generator: %v", err)
	}

	fmt.Println("[INFO] Generating charts...")

	switch *chartType {
	case "throughput":
		err = generator.GenerateThroughputChart()
	case "latency":
		err = generator.GenerateLatencyChart()
	case "combined":
		err = generator.GenerateCombinedChart()
	case "dashboard":
		err = generator.GenerateDashboard()
	case "all":
		err = generator.GenerateAllCharts()
	default:
		log.Fatalf("[ERROR] Unknown chart type: %s", *chartType)
	}

	if err != nil {
		log.Fatalf("[ERROR] Failed to generate charts: %v", err)
	}

	fmt.Println("[SUCCESS] Charts generated successfully!")
}

func showUsage() {
	fmt.Printf(`Usage: %s [OPTIONS]

Generate interactive HTML charts from NFS vs Direct Storage benchmark results.

Options:
    -input FILE       Path to JSON results file (if not provided, finds latest)
    -output DIR       Output directory for charts (default: same as input file)
    -chart TYPE       Chart type: throughput, latency, combined, dashboard, all (default: all)
    -help            Show this help message

Examples:
    %s -input results.json
    %s -input results.json -chart throughput -output charts/
    %s -chart dashboard

Chart Types:
    throughput - Operations per second comparison
    latency    - Latency distribution (P50, P90, P95, P99)
    combined   - Side-by-side throughput and key latency metrics
    dashboard  - Comprehensive view with all metrics
    all        - Generate all chart types (default)

`, os.Args[0], os.Args[0], os.Args[0], os.Args[0])
}

func findLatestResults() (string, error) {
	resultsDir := "./results"
	if _, err := os.Stat(resultsDir); os.IsNotExist(err) {
		return "", fmt.Errorf("results directory not found: %s", resultsDir)
	}

	var jsonFiles []string
	err := filepath.WalkDir(resultsDir, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if !d.IsDir() && strings.HasSuffix(path, ".json") {
			jsonFiles = append(jsonFiles, path)
		}
		return nil
	})
	if err != nil {
		return "", err
	}

	if len(jsonFiles) == 0 {
		return "", fmt.Errorf("no JSON files found in %s", resultsDir)
	}

	// Sort files by modification time (newest first)
	sort.Slice(jsonFiles, func(i, j int) bool {
		infoI, _ := os.Stat(jsonFiles[i])
		infoJ, _ := os.Stat(jsonFiles[j])
		return infoI.ModTime().After(infoJ.ModTime())
	})

	return jsonFiles[0], nil
}

func NewChartGenerator(inputFile, outputDir string) (*ChartGenerator, error) {
	data, err := os.ReadFile(inputFile)
	if err != nil {
		return nil, fmt.Errorf("failed to read input file: %w", err)
	}

	var results BenchmarkResults
	if err := json.Unmarshal(data, &results); err != nil {
		return nil, fmt.Errorf("failed to parse JSON: %w", err)
	}

	if err := os.MkdirAll(outputDir, 0755); err != nil {
		return nil, fmt.Errorf("failed to create output directory: %w", err)
	}

	return &ChartGenerator{
		results:   results,
		outputDir: outputDir,
	}, nil
}

func (cg *ChartGenerator) GenerateThroughputChart() error {
	bar := charts.NewBar()
	bar.SetGlobalOptions(
		charts.WithTitleOpts(opts.Title{
			Title:    "Throughput Comparison: NFS vs Direct Storage",
			Subtitle: "Operations per second - Higher is Better",
		}),
		charts.WithYAxisOpts(opts.YAxis{
			Name: "Operations per Second",
		}),
		charts.WithLegendOpts(opts.Legend{
			Show: true,
		}),
		charts.WithInitializationOpts(opts.Initialization{
			Theme: types.ThemeWesteros,
		}),
	)

	// Add data
	directOps := cg.results.Direct.Metrics.OperationsPerSecond
	nfsOps := cg.results.NFS.Metrics.OperationsPerSecond
	
	bar.SetXAxis([]string{"Direct Storage", "NFS Storage"}).
		AddSeries("Throughput", []opts.BarData{
			{Value: math.Round(directOps*10)/10, ItemStyle: &opts.ItemStyle{Color: "#007AFF"}},
			{Value: math.Round(nfsOps*10)/10, ItemStyle: &opts.ItemStyle{Color: "#FF6B35"}},
		})

	// Calculate performance difference
	diff := ((directOps - nfsOps) / directOps) * 100
	bar.SetGlobalOptions(
		charts.WithTitleOpts(opts.Title{
			Title:    "Throughput Comparison: NFS vs Direct Storage",
			Subtitle: fmt.Sprintf("Operations per second - NFS is %.1f%% slower", diff),
		}),
	)

	outputFile := filepath.Join(cg.outputDir, "throughput_chart.html")
	f, err := os.Create(outputFile)
	if err != nil {
		return err
	}
	defer f.Close()

	err = bar.Render(f)
	if err != nil {
		return err
	}

	fmt.Printf("[INFO] Throughput chart saved: %s\n", outputFile)
	return nil
}

func (cg *ChartGenerator) GenerateLatencyChart() error {
	bar := charts.NewBar()
	bar.SetGlobalOptions(
		charts.WithTitleOpts(opts.Title{
			Title:    "Latency Distribution: NFS vs Direct Storage",
			Subtitle: "Response time in milliseconds - Lower is Better",
		}),
		charts.WithYAxisOpts(opts.YAxis{
			Name: "Latency (milliseconds)",
		}),
		charts.WithLegendOpts(opts.Legend{
			Show: true,
		}),
		charts.WithInitializationOpts(opts.Initialization{
			Theme: types.ThemeWesteros,
		}),
	)

	// Convert nanoseconds to milliseconds
	directMetrics := []float64{
		float64(cg.results.Direct.Metrics.AverageLatency) / 1000000,
		float64(cg.results.Direct.Metrics.P50Latency) / 1000000,
		float64(cg.results.Direct.Metrics.P90Latency) / 1000000,
		float64(cg.results.Direct.Metrics.P95Latency) / 1000000,
		float64(cg.results.Direct.Metrics.P99Latency) / 1000000,
	}

	nfsMetrics := []float64{
		float64(cg.results.NFS.Metrics.AverageLatency) / 1000000,
		float64(cg.results.NFS.Metrics.P50Latency) / 1000000,
		float64(cg.results.NFS.Metrics.P90Latency) / 1000000,
		float64(cg.results.NFS.Metrics.P95Latency) / 1000000,
		float64(cg.results.NFS.Metrics.P99Latency) / 1000000,
	}

	labels := []string{"Average", "P50", "P90", "P95", "P99"}

	bar.SetXAxis(labels)

	// Add Direct Storage series
	var directData []opts.BarData
	for _, val := range directMetrics {
		directData = append(directData, opts.BarData{
			Value: math.Round(val*10)/10,
			ItemStyle: &opts.ItemStyle{Color: "#007AFF"},
		})
	}

	// Add NFS Storage series
	var nfsData []opts.BarData
	for _, val := range nfsMetrics {
		nfsData = append(nfsData, opts.BarData{
			Value: math.Round(val*10)/10,
			ItemStyle: &opts.ItemStyle{Color: "#FF6B35"},
		})
	}

	bar.AddSeries("Direct Storage", directData).
		AddSeries("NFS Storage", nfsData)

	outputFile := filepath.Join(cg.outputDir, "latency_chart.html")
	f, err := os.Create(outputFile)
	if err != nil {
		return err
	}
	defer f.Close()

	err = bar.Render(f)
	if err != nil {
		return err
	}

	fmt.Printf("[INFO] Latency chart saved: %s\n", outputFile)
	return nil
}

func (cg *ChartGenerator) GenerateCombinedChart() error {
	page := components.NewPage()
	page.SetLayout(components.PageFlexLayout)

	// Create throughput chart
	throughputBar := charts.NewBar()
	throughputBar.SetGlobalOptions(
		charts.WithTitleOpts(opts.Title{
			Title: "Throughput Comparison",
		}),
		charts.WithYAxisOpts(opts.YAxis{
			Name: "Operations/sec",
		}),
	)

	directOps := cg.results.Direct.Metrics.OperationsPerSecond
	nfsOps := cg.results.NFS.Metrics.OperationsPerSecond

	throughputBar.SetXAxis([]string{"Direct", "NFS"}).
		AddSeries("Throughput", []opts.BarData{
			{Value: math.Round(directOps*10)/10, ItemStyle: &opts.ItemStyle{Color: "#007AFF"}},
			{Value: math.Round(nfsOps*10)/10, ItemStyle: &opts.ItemStyle{Color: "#FF6B35"}},
		})

	// Create key latency chart
	latencyBar := charts.NewBar()
	latencyBar.SetGlobalOptions(
		charts.WithTitleOpts(opts.Title{
			Title: "Key Latency Metrics",
		}),
		charts.WithYAxisOpts(opts.YAxis{
			Name: "Latency (ms)",
		}),
		charts.WithLegendOpts(opts.Legend{
			Show: true,
		}),
	)

	avgDirect := float64(cg.results.Direct.Metrics.AverageLatency) / 1000000
	avgNFS := float64(cg.results.NFS.Metrics.AverageLatency) / 1000000
	p95Direct := float64(cg.results.Direct.Metrics.P95Latency) / 1000000
	p95NFS := float64(cg.results.NFS.Metrics.P95Latency) / 1000000

	latencyBar.SetXAxis([]string{"Average", "P95"}).
		AddSeries("Direct", []opts.BarData{
			{Value: math.Round(avgDirect*10)/10, ItemStyle: &opts.ItemStyle{Color: "#007AFF"}},
			{Value: math.Round(p95Direct*10)/10, ItemStyle: &opts.ItemStyle{Color: "#007AFF"}},
		}).
		AddSeries("NFS", []opts.BarData{
			{Value: math.Round(avgNFS*10)/10, ItemStyle: &opts.ItemStyle{Color: "#FF6B35"}},
			{Value: math.Round(p95NFS*10)/10, ItemStyle: &opts.ItemStyle{Color: "#FF6B35"}},
		})

	page.AddCharts(throughputBar, latencyBar)

	outputFile := filepath.Join(cg.outputDir, "combined_chart.html")
	f, err := os.Create(outputFile)
	if err != nil {
		return err
	}
	defer f.Close()

	err = page.Render(f)
	if err != nil {
		return err
	}

	fmt.Printf("[INFO] Combined chart saved: %s\n", outputFile)
	return nil
}

func (cg *ChartGenerator) GenerateDashboard() error {
	page := components.NewPage()
	page.SetLayout(components.PageFlexLayout)

	// 1. Throughput comparison
	throughputChart := cg.createThroughputChart()
	
	// 2. Latency distribution
	latencyChart := cg.createLatencyChart()
	
	// 3. Performance summary table
	summaryChart := cg.createSummaryChart()
	
	// 4. Duration comparison
	durationChart := cg.createDurationChart()

	page.AddCharts(
		throughputChart,
		latencyChart,
		summaryChart,
		durationChart,
	)

	outputFile := filepath.Join(cg.outputDir, "dashboard.html")
	f, err := os.Create(outputFile)
	if err != nil {
		return err
	}
	defer f.Close()

	err = page.Render(f)
	if err != nil {
		return err
	}

	fmt.Printf("[INFO] Dashboard saved: %s\n", outputFile)
	return nil
}

func (cg *ChartGenerator) createThroughputChart() *charts.Bar {
	bar := charts.NewBar()
	bar.SetGlobalOptions(
		charts.WithTitleOpts(opts.Title{
			Title: "Throughput Comparison",
		}),
	)

	directOps := cg.results.Direct.Metrics.OperationsPerSecond
	nfsOps := cg.results.NFS.Metrics.OperationsPerSecond

	bar.SetXAxis([]string{"Direct Storage", "NFS Storage"}).
		AddSeries("Ops/sec", []opts.BarData{
			{Value: math.Round(directOps*10)/10, ItemStyle: &opts.ItemStyle{Color: "#007AFF"}},
			{Value: math.Round(nfsOps*10)/10, ItemStyle: &opts.ItemStyle{Color: "#FF6B35"}},
		})

	return bar
}

func (cg *ChartGenerator) createLatencyChart() *charts.Bar {
	bar := charts.NewBar()
	bar.SetGlobalOptions(
		charts.WithTitleOpts(opts.Title{
			Title: "Latency Distribution",
		}),
		charts.WithLegendOpts(opts.Legend{Show: true}),
	)

	labels := []string{"Average", "P90", "P95", "P99"}
	
	directLatencies := []float64{
		float64(cg.results.Direct.Metrics.AverageLatency) / 1000000,
		float64(cg.results.Direct.Metrics.P90Latency) / 1000000,
		float64(cg.results.Direct.Metrics.P95Latency) / 1000000,
		float64(cg.results.Direct.Metrics.P99Latency) / 1000000,
	}

	nfsLatencies := []float64{
		float64(cg.results.NFS.Metrics.AverageLatency) / 1000000,
		float64(cg.results.NFS.Metrics.P90Latency) / 1000000,
		float64(cg.results.NFS.Metrics.P95Latency) / 1000000,
		float64(cg.results.NFS.Metrics.P99Latency) / 1000000,
	}

	var directData, nfsData []opts.BarData
	for _, val := range directLatencies {
		directData = append(directData, opts.BarData{Value: math.Round(val*10)/10})
	}
	for _, val := range nfsLatencies {
		nfsData = append(nfsData, opts.BarData{Value: math.Round(val*10)/10})
	}

	bar.SetXAxis(labels).
		AddSeries("Direct", directData).
		AddSeries("NFS", nfsData)

	return bar
}

func (cg *ChartGenerator) createSummaryChart() *charts.Bar {
	// Performance impact summary
	bar := charts.NewBar()
	bar.SetGlobalOptions(
		charts.WithTitleOpts(opts.Title{
			Title: "Performance Impact Summary",
		}),
	)

	directOps := cg.results.Direct.Metrics.OperationsPerSecond
	nfsOps := cg.results.NFS.Metrics.OperationsPerSecond
	throughputOverhead := ((directOps - nfsOps) / directOps) * 100

	directLatency := float64(cg.results.Direct.Metrics.AverageLatency) / 1000000
	nfsLatency := float64(cg.results.NFS.Metrics.AverageLatency) / 1000000
	latencyOverhead := ((nfsLatency - directLatency) / directLatency) * 100

	bar.SetXAxis([]string{"Throughput Reduction", "Latency Increase"}).
		AddSeries("NFS Overhead (%)", []opts.BarData{
			{Value: math.Round(throughputOverhead*10)/10, ItemStyle: &opts.ItemStyle{Color: "#FF6B35"}},
			{Value: math.Round(latencyOverhead*10)/10, ItemStyle: &opts.ItemStyle{Color: "#FF6B35"}},
		})

	return bar
}

func (cg *ChartGenerator) createDurationChart() *charts.Bar {
	bar := charts.NewBar()
	bar.SetGlobalOptions(
		charts.WithTitleOpts(opts.Title{
			Title: "Test Duration",
		}),
	)

	directDuration := float64(cg.results.Direct.Duration) / 1000000000 // Convert to seconds
	nfsDuration := float64(cg.results.NFS.Duration) / 1000000000

	bar.SetXAxis([]string{"Direct Storage", "NFS Storage"}).
		AddSeries("Duration (seconds)", []opts.BarData{
			{Value: math.Round(directDuration*10)/10, ItemStyle: &opts.ItemStyle{Color: "#28a745"}},
			{Value: math.Round(nfsDuration*10)/10, ItemStyle: &opts.ItemStyle{Color: "#dc3545"}},
		})

	return bar
}

func (cg *ChartGenerator) GenerateAllCharts() error {
	if err := cg.GenerateThroughputChart(); err != nil {
		return fmt.Errorf("failed to generate throughput chart: %w", err)
	}

	if err := cg.GenerateLatencyChart(); err != nil {
		return fmt.Errorf("failed to generate latency chart: %w", err)
	}

	if err := cg.GenerateCombinedChart(); err != nil {
		return fmt.Errorf("failed to generate combined chart: %w", err)
	}

	if err := cg.GenerateDashboard(); err != nil {
		return fmt.Errorf("failed to generate dashboard: %w", err)
	}

	return nil
}
