package database

import (
	"encoding/json"
	"fmt"
	"math/rand"
	"time"
)

// BenchmarkRecord represents a single record for benchmark testing
type BenchmarkRecord struct {
	Text   string
	Number int
	JSON   string
}

// Database interface for database operations
type Database interface {
	CreateBenchmarkTable() error
	ClearBenchmarkTable() error
	InsertBatch(batch []BenchmarkRecord) error
	CountRecords() (int, error)
	GetName() string
	GetStats() (map[string]interface{}, error)
	Close() error
}

// RecordSize represents the size of benchmark records
type RecordSize string

const (
	RecordSizeSmall  RecordSize = "small"
	RecordSizeMedium RecordSize = "medium"
	RecordSizeLarge  RecordSize = "large"
)

// GenerateBenchmarkRecords creates a batch of benchmark records
func GenerateBenchmarkRecords(count int, size RecordSize) []BenchmarkRecord {
	records := make([]BenchmarkRecord, count)
	
	for i := 0; i < count; i++ {
		records[i] = generateRecord(i, size)
	}
	
	return records
}

func generateRecord(id int, size RecordSize) BenchmarkRecord {
	var textSize int
	var jsonData map[string]interface{}
	
	switch size {
	case RecordSizeSmall:
		textSize = 50 + rand.Intn(50)  // 50-100 chars
		jsonData = map[string]interface{}{
			"id": id,
			"type": "small",
		}
	case RecordSizeMedium:
		textSize = 200 + rand.Intn(200) // 200-400 chars  
		jsonData = map[string]interface{}{
			"id": id,
			"type": "medium",
			"data": generateRandomString(100),
			"timestamp": time.Now().Unix(),
		}
	case RecordSizeLarge:
		textSize = 500 + rand.Intn(500) // 500-1000 chars
		jsonData = map[string]interface{}{
			"id": id,
			"type": "large",
			"data": generateRandomString(200),
			"metadata": map[string]interface{}{
				"created": time.Now().Format(time.RFC3339),
				"version": "1.0",
				"tags": []string{"benchmark", "test", "large"},
			},
			"content": generateRandomString(300),
		}
	default:
		textSize = 100
		jsonData = map[string]interface{}{"id": id}
	}
	
	jsonStr, _ := json.Marshal(jsonData)
	
	return BenchmarkRecord{
		Text:   generateRandomString(textSize),
		Number: rand.Intn(1000000),
		JSON:   string(jsonStr),
	}
}

func generateRandomString(length int) string {
	const charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 .,!?-"
	result := make([]byte, length)
	
	for i := range result {
		result[i] = charset[rand.Intn(len(charset))]
	}
	
	return string(result)
}

// FormatBytes formats byte counts into human readable format
func FormatBytes(bytes int64) string {
	const unit = 1024
	if bytes < unit {
		return fmt.Sprintf("%d B", bytes)
	}
	div, exp := int64(unit), 0
	for n := bytes / unit; n >= unit; n /= unit {
		div *= unit
		exp++
	}
	return fmt.Sprintf("%.1f %cB", float64(bytes)/float64(div), "KMGTPE"[exp])
}
