package cli

import (
	"context"
	"fmt"
	"log"
	"strings"

	"github.com/spf13/cobra"
	"github.com/spf13/viper"

	"github.com/l22io/nfsvsdirectbench/internal/benchmark"
	"github.com/l22io/nfsvsdirectbench/internal/config"
)

var (
	databases    []string
	scenarios    []string
	storageTypes []string
	nfsVersions  []string
	dryRun       bool
	outputDir    string
)

var runCmd = &cobra.Command{
	Use:   "run",
	Short: "Run benchmark suite",
	Long: `Run the complete NFS vs Direct Storage benchmark suite.

This command orchestrates the benchmark execution across all enabled 
databases and scenarios, comparing NFS storage performance against 
direct block storage.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		cfg, err := config.Load()
		if err != nil {
			return fmt.Errorf("failed to load configuration: %w", err)
		}

		// Override config with CLI flags
		if len(databases) > 0 {
			cfg.FilterDatabases(databases)
		}
		if len(scenarios) > 0 {
			cfg.FilterScenarios(scenarios)
		}
		if outputDir != "" {
			cfg.Global.OutputDir = outputDir
		}

		if dryRun {
			return showExecutionPlan(cfg)
		}

		return runBenchmark(cfg)
	},
}

func init() {
	rootCmd.AddCommand(runCmd)

	runCmd.Flags().StringSliceVarP(&databases, "databases", "d", nil, 
		"Specific databases to benchmark (postgresql,mysql,sqlite)")
	runCmd.Flags().StringSliceVarP(&scenarios, "scenarios", "s", nil,
		"Specific scenarios to run")
	runCmd.Flags().StringSliceVar(&storageTypes, "storage-types", []string{"direct", "nfs"},
		"Storage types to benchmark")
	runCmd.Flags().StringSliceVar(&nfsVersions, "nfs-versions", nil,
		"NFS versions to test (v3,v4)")
	runCmd.Flags().BoolVar(&dryRun, "dry-run", false,
		"Show execution plan without running benchmarks")
	runCmd.Flags().StringVarP(&outputDir, "output", "o", "",
		"Output directory for results")
}

func showExecutionPlan(cfg *config.Config) error {
	fmt.Println("Execution Plan:")
	fmt.Println("===============")
	fmt.Println()
	
	fmt.Println("Enabled Databases:")
	for _, db := range cfg.GetEnabledDatabases() {
		fmt.Printf("  - %s\n", db)
	}
	fmt.Println()
	
	fmt.Println("Enabled Scenarios:")
	for _, scenario := range cfg.GetEnabledScenarios() {
		fmt.Printf("  - %s: %s\n", scenario.Name, scenario.Description)
		fmt.Printf("    Duration: %ds\n", scenario.Duration)
	}
	fmt.Println()
	
	fmt.Println("NFS Configurations:")
	for _, version := range cfg.NFS.Versions {
		fmt.Printf("  - NFS %s\n", version)
	}
	for _, mountOpt := range cfg.NFS.MountOptions {
		fmt.Printf("    %s: %s\n", mountOpt.Name, mountOpt.Options)
	}
	fmt.Println()
	
	fmt.Printf("Output Directory: %s\n", cfg.Global.OutputDir)
	
	return nil
}

func runBenchmark(cfg *config.Config) error {
	ctx := context.Background()
	
	if viper.GetBool("verbose") {
		log.Printf("Starting benchmark with config: %+v", cfg)
	}
	
	runner := benchmark.NewRunner(cfg)
	
	results, err := runner.RunAll(ctx)
	if err != nil {
		return fmt.Errorf("benchmark failed: %w", err)
	}
	
	fmt.Printf("Benchmark completed successfully\n")
	fmt.Printf("Results saved to: %s\n", results.OutputDir)
	
	// Print summary
	fmt.Println("\nSummary:")
	fmt.Printf("- Databases tested: %s\n", strings.Join(cfg.GetEnabledDatabases(), ", "))
	fmt.Printf("- Scenarios executed: %d\n", len(cfg.GetEnabledScenarios()))
	fmt.Printf("- Total runtime: %s\n", results.TotalDuration.String())
	
	return nil
}
