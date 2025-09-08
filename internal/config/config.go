package config

import (
	"fmt"
	"time"

	"github.com/spf13/viper"
)

// Config represents the complete benchmark configuration
type Config struct {
	Global    GlobalConfig              `mapstructure:"global"`
	Databases map[string]DatabaseConfig `mapstructure:"databases"`
	NFS       NFSConfig                 `mapstructure:"nfs"`
	Scenarios []ScenarioConfig          `mapstructure:"scenarios"`
	Metrics   MetricsConfig             `mapstructure:"metrics"`
	Reporting ReportingConfig           `mapstructure:"reporting"`
	Execution ExecutionConfig           `mapstructure:"execution"`
}

// GlobalConfig contains global benchmark settings
type GlobalConfig struct {
	OutputDir       string `mapstructure:"output_dir"`
	TimestampFormat string `mapstructure:"timestamp_format"`
	LogLevel        string `mapstructure:"log_level"`
	MaxWorkers      int    `mapstructure:"max_workers"`
}

// DatabaseConfig contains database connection settings
type DatabaseConfig struct {
	Enabled bool                      `mapstructure:"enabled"`
	Direct  DatabaseConnectionConfig  `mapstructure:"direct"`
	NFS     DatabaseConnectionConfig  `mapstructure:"nfs"`
}

// DatabaseConnectionConfig contains connection parameters
type DatabaseConnectionConfig struct {
	Host     string `mapstructure:"host"`
	Port     int    `mapstructure:"port"`
	Database string `mapstructure:"database"`
	Username string `mapstructure:"username"`
	Password string `mapstructure:"password"`
	Path     string `mapstructure:"path"` // For SQLite
}

// NFSConfig contains NFS testing parameters
type NFSConfig struct {
	Versions     []string           `mapstructure:"versions"`
	MountOptions []NFSMountOption   `mapstructure:"mount_options"`
}

// NFSMountOption represents NFS mount configuration
type NFSMountOption struct {
	Name    string `mapstructure:"name"`
	Options string `mapstructure:"options"`
}

// ScenarioConfig defines a benchmark scenario
type ScenarioConfig struct {
	Name        string                 `mapstructure:"name"`
	Description string                 `mapstructure:"description"`
	Enabled     bool                   `mapstructure:"enabled"`
	Duration    int                    `mapstructure:"duration"` // seconds
	Parameters  map[string]interface{} `mapstructure:"parameters"`
}

// MetricsConfig defines metrics collection settings
type MetricsConfig struct {
	CollectionInterval   int            `mapstructure:"collection_interval"`
	SystemMetrics       SystemMetrics  `mapstructure:"system_metrics"`
	DatabaseMetrics     DatabaseMetrics `mapstructure:"database_metrics"`
	LatencyPercentiles  []float64      `mapstructure:"latency_percentiles"`
}

// SystemMetrics defines system-level metrics to collect
type SystemMetrics struct {
	CPU       bool `mapstructure:"cpu"`
	Memory    bool `mapstructure:"memory"`
	DiskIO    bool `mapstructure:"disk_io"`
	NetworkIO bool `mapstructure:"network_io"`
}

// DatabaseMetrics defines database-specific metrics
type DatabaseMetrics struct {
	Connections bool `mapstructure:"connections"`
	QueryStats  bool `mapstructure:"query_stats"`
	LockStats   bool `mapstructure:"lock_stats"`
	BufferStats bool `mapstructure:"buffer_stats"`
}

// ReportingConfig defines output and reporting options
type ReportingConfig struct {
	Formats    []string          `mapstructure:"formats"`
	CLI        CLIReporting      `mapstructure:"cli"`
	HTML       HTMLReporting     `mapstructure:"html"`
	Comparison ComparisonConfig  `mapstructure:"comparison"`
}

// CLIReporting defines CLI output settings
type CLIReporting struct {
	RealTimeUpdates   bool `mapstructure:"real_time_updates"`
	ShowProgressBars  bool `mapstructure:"show_progress_bars"`
}

// HTMLReporting defines HTML report settings
type HTMLReporting struct {
	IncludeCharts bool   `mapstructure:"include_charts"`
	Interactive   bool   `mapstructure:"interactive"`
	Template      string `mapstructure:"template"`
}

// ComparisonConfig defines comparison analysis settings
type ComparisonConfig struct {
	StatisticalAnalysis   bool    `mapstructure:"statistical_analysis"`
	SignificanceThreshold float64 `mapstructure:"significance_threshold"`
	MinimumSamples        int     `mapstructure:"minimum_samples"`
}

// ExecutionConfig defines test execution parameters
type ExecutionConfig struct {
	WarmupDuration  int               `mapstructure:"warmup_duration"`  // seconds
	CooldownDuration int              `mapstructure:"cooldown_duration"` // seconds
	RepeatCount     int               `mapstructure:"repeat_count"`
	RandomizeOrder  bool              `mapstructure:"randomize_order"`
	FailFast        bool              `mapstructure:"fail_fast"`
	Cleanup         CleanupConfig     `mapstructure:"cleanup"`
}

// CleanupConfig defines cleanup behavior
type CleanupConfig struct {
	ResetDatabases  bool `mapstructure:"reset_databases"`
	ClearCaches     bool `mapstructure:"clear_caches"`
	RestartServices bool `mapstructure:"restart_services"`
}

// Load loads configuration from file and environment
func Load() (*Config, error) {
	var cfg Config
	
	if err := viper.Unmarshal(&cfg); err != nil {
		return nil, fmt.Errorf("failed to unmarshal config: %w", err)
	}
	
	// Set defaults
	if cfg.Global.OutputDir == "" {
		cfg.Global.OutputDir = "./results"
	}
	if cfg.Global.TimestampFormat == "" {
		cfg.Global.TimestampFormat = "20060102_150405"
	}
	if cfg.Global.LogLevel == "" {
		cfg.Global.LogLevel = "INFO"
	}
	if cfg.Global.MaxWorkers == 0 {
		cfg.Global.MaxWorkers = 4
	}
	
	return &cfg, nil
}

// GetEnabledDatabases returns list of enabled database names
func (c *Config) GetEnabledDatabases() []string {
	var enabled []string
	for name, dbConfig := range c.Databases {
		if dbConfig.Enabled {
			enabled = append(enabled, name)
		}
	}
	return enabled
}

// GetEnabledScenarios returns list of enabled scenarios
func (c *Config) GetEnabledScenarios() []ScenarioConfig {
	var enabled []ScenarioConfig
	for _, scenario := range c.Scenarios {
		if scenario.Enabled {
			enabled = append(enabled, scenario)
		}
	}
	return enabled
}

// FilterDatabases enables only specified databases
func (c *Config) FilterDatabases(databases []string) {
	dbSet := make(map[string]bool)
	for _, db := range databases {
		dbSet[db] = true
	}
	
	for name := range c.Databases {
		dbConfig := c.Databases[name]
		dbConfig.Enabled = dbSet[name]
		c.Databases[name] = dbConfig
	}
}

// FilterScenarios enables only specified scenarios
func (c *Config) FilterScenarios(scenarios []string) {
	scenarioSet := make(map[string]bool)
	for _, s := range scenarios {
		scenarioSet[s] = true
	}
	
	for i := range c.Scenarios {
		c.Scenarios[i].Enabled = scenarioSet[c.Scenarios[i].Name]
	}
}

// GetWarmupDuration returns warmup duration as time.Duration
func (c *Config) GetWarmupDuration() time.Duration {
	return time.Duration(c.Execution.WarmupDuration) * time.Second
}

// GetCooldownDuration returns cooldown duration as time.Duration
func (c *Config) GetCooldownDuration() time.Duration {
	return time.Duration(c.Execution.CooldownDuration) * time.Second
}
