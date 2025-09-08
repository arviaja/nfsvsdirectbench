package config

import (
	"testing"

	"github.com/spf13/viper"
)

func TestLoad(t *testing.T) {
	// Set up viper with test config
	viper.Set("global.output_dir", "./test_results")
	viper.Set("global.log_level", "DEBUG")
	viper.Set("databases.postgresql.enabled", true)
	viper.Set("databases.mysql.enabled", false)
	viper.Set("databases.sqlite.enabled", true)
	
	cfg, err := Load()
	if err != nil {
		t.Fatalf("Failed to load config: %v", err)
	}
	
	if cfg.Global.OutputDir != "./test_results" {
		t.Errorf("Expected output_dir './test_results', got '%s'", cfg.Global.OutputDir)
	}
	
	if cfg.Global.LogLevel != "DEBUG" {
		t.Errorf("Expected log_level 'DEBUG', got '%s'", cfg.Global.LogLevel)
	}
}

func TestGetEnabledDatabases(t *testing.T) {
	cfg := &Config{
		Databases: map[string]DatabaseConfig{
			"postgresql": {Enabled: true},
			"mysql":      {Enabled: false},
			"sqlite":     {Enabled: true},
		},
	}
	
	enabled := cfg.GetEnabledDatabases()
	
	if len(enabled) != 2 {
		t.Errorf("Expected 2 enabled databases, got %d", len(enabled))
	}
	
	// Note: order may vary due to map iteration
	hasPostgres := false
	hasSQLite := false
	for _, db := range enabled {
		if db == "postgresql" {
			hasPostgres = true
		}
		if db == "sqlite" {
			hasSQLite = true
		}
	}
	
	if !hasPostgres {
		t.Error("Expected postgresql to be enabled")
	}
	if !hasSQLite {
		t.Error("Expected sqlite to be enabled")
	}
}

func TestGetEnabledScenarios(t *testing.T) {
	cfg := &Config{
		Scenarios: []ScenarioConfig{
			{Name: "test1", Enabled: true},
			{Name: "test2", Enabled: false},
			{Name: "test3", Enabled: true},
		},
	}
	
	enabled := cfg.GetEnabledScenarios()
	
	if len(enabled) != 2 {
		t.Errorf("Expected 2 enabled scenarios, got %d", len(enabled))
	}
	
	if enabled[0].Name != "test1" && enabled[1].Name != "test1" {
		t.Error("Expected test1 to be in enabled scenarios")
	}
	if enabled[0].Name != "test3" && enabled[1].Name != "test3" {
		t.Error("Expected test3 to be in enabled scenarios")
	}
}
