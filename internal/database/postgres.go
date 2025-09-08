package database

import (
	"database/sql"
	"fmt"
	"time"

	_ "github.com/lib/pq"
	"github.com/l22io/nfsvsdirectbench/internal/config"
)

// PostgresDB represents a PostgreSQL database connection
type PostgresDB struct {
	db     *sql.DB
	config config.DatabaseConnectionConfig
	name   string
}

// NewPostgresDB creates a new PostgreSQL database connection
func NewPostgresDB(cfg config.DatabaseConnectionConfig, name string) (*PostgresDB, error) {
	connStr := fmt.Sprintf("host=%s port=%d user=%s password=%s dbname=%s sslmode=disable",
		cfg.Host, cfg.Port, cfg.Username, cfg.Password, cfg.Database)

	db, err := sql.Open("postgres", connStr)
	if err != nil {
		return nil, fmt.Errorf("failed to open database: %w", err)
	}

	// Configure connection pool
	db.SetMaxOpenConns(25)
	db.SetMaxIdleConns(5)
	db.SetConnMaxLifetime(5 * time.Minute)

	// Test connection
	if err := db.Ping(); err != nil {
		return nil, fmt.Errorf("failed to ping database: %w", err)
	}

	return &PostgresDB{
		db:     db,
		config: cfg,
		name:   name,
	}, nil
}

// Close closes the database connection
func (p *PostgresDB) Close() error {
	return p.db.Close()
}

// CreateBenchmarkTable creates the benchmark table for testing
func (p *PostgresDB) CreateBenchmarkTable() error {
	query := `
		CREATE TABLE IF NOT EXISTS benchmark_data (
			id SERIAL PRIMARY KEY,
			data_text VARCHAR(1000),
			data_int INTEGER,
			data_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
			data_json JSONB
		)
	`
	_, err := p.db.Exec(query)
	return err
}

// ClearBenchmarkTable clears all data from the benchmark table
func (p *PostgresDB) ClearBenchmarkTable() error {
	_, err := p.db.Exec("TRUNCATE TABLE benchmark_data RESTART IDENTITY")
	return err
}

// InsertBatch inserts a batch of records
func (p *PostgresDB) InsertBatch(batch []BenchmarkRecord) error {
	tx, err := p.db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	stmt, err := tx.Prepare("INSERT INTO benchmark_data (data_text, data_int, data_json) VALUES ($1, $2, $3)")
	if err != nil {
		return err
	}
	defer stmt.Close()

	for _, record := range batch {
		_, err := stmt.Exec(record.Text, record.Number, record.JSON)
		if err != nil {
			return err
		}
	}

	return tx.Commit()
}

// CountRecords returns the total number of records in the benchmark table
func (p *PostgresDB) CountRecords() (int, error) {
	var count int
	err := p.db.QueryRow("SELECT COUNT(*) FROM benchmark_data").Scan(&count)
	return count, err
}

// GetName returns the database connection name
func (p *PostgresDB) GetName() string {
	return p.name
}

// GetStats returns database statistics
func (p *PostgresDB) GetStats() (map[string]interface{}, error) {
	stats := make(map[string]interface{})
	
	// Get connection stats
	dbStats := p.db.Stats()
	stats["max_open_connections"] = dbStats.MaxOpenConnections
	stats["open_connections"] = dbStats.OpenConnections
	stats["in_use"] = dbStats.InUse
	stats["idle"] = dbStats.Idle

	// Get table size
	var tableSize int64
	err := p.db.QueryRow(`
		SELECT pg_total_relation_size('benchmark_data')
	`).Scan(&tableSize)
	if err != nil {
		tableSize = 0
	}
	stats["table_size_bytes"] = tableSize

	return stats, nil
}
