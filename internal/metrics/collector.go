package metrics

import (
	"sort"
	"sync"
	"time"
)

// Collector collects and analyzes benchmark metrics
type Collector struct {
	mu        sync.RWMutex
	latencies []time.Duration
	startTime time.Time
	endTime   time.Time
	errors    []error
	throughput int64
}

// NewCollector creates a new metrics collector
func NewCollector() *Collector {
	return &Collector{
		latencies: make([]time.Duration, 0),
		errors:    make([]error, 0),
	}
}

// Start marks the beginning of measurement
func (c *Collector) Start() {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.startTime = time.Now()
}

// End marks the end of measurement
func (c *Collector) End() {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.endTime = time.Now()
}

// AddLatency records a latency measurement
func (c *Collector) AddLatency(latency time.Duration) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.latencies = append(c.latencies, latency)
}

// AddError records an error
func (c *Collector) AddError(err error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.errors = append(c.errors, err)
}

// SetThroughput sets the total throughput (operations completed)
func (c *Collector) SetThroughput(ops int64) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.throughput = ops
}

// Results returns the collected metrics
func (c *Collector) Results() *Results {
	c.mu.RLock()
	defer c.mu.RUnlock()

	if len(c.latencies) == 0 {
		return &Results{
			TotalDuration: c.endTime.Sub(c.startTime),
			ErrorCount:    len(c.errors),
			Throughput:    c.throughput,
		}
	}

	// Sort latencies for percentile calculation
	sorted := make([]time.Duration, len(c.latencies))
	copy(sorted, c.latencies)
	sort.Slice(sorted, func(i, j int) bool {
		return sorted[i] < sorted[j]
	})

	totalDuration := c.endTime.Sub(c.startTime)
	
	results := &Results{
		TotalDuration:    totalDuration,
		TotalOperations:  int64(len(c.latencies)),
		Throughput:       c.throughput,
		ErrorCount:       len(c.errors),
		AverageLatency:   c.calculateAverage(sorted),
		P50Latency:      c.calculatePercentile(sorted, 50),
		P90Latency:      c.calculatePercentile(sorted, 90),
		P95Latency:      c.calculatePercentile(sorted, 95),
		P99Latency:      c.calculatePercentile(sorted, 99),
		P999Latency:     c.calculatePercentile(sorted, 99.9),
		MinLatency:      sorted[0],
		MaxLatency:      sorted[len(sorted)-1],
	}

	// Calculate operations per second
	if totalDuration.Seconds() > 0 {
		results.OperationsPerSecond = float64(results.TotalOperations) / totalDuration.Seconds()
	}

	return results
}

func (c *Collector) calculateAverage(latencies []time.Duration) time.Duration {
	if len(latencies) == 0 {
		return 0
	}
	
	var total time.Duration
	for _, lat := range latencies {
		total += lat
	}
	
	return total / time.Duration(len(latencies))
}

func (c *Collector) calculatePercentile(sortedLatencies []time.Duration, percentile float64) time.Duration {
	if len(sortedLatencies) == 0 {
		return 0
	}
	
	if percentile <= 0 {
		return sortedLatencies[0]
	}
	
	if percentile >= 100 {
		return sortedLatencies[len(sortedLatencies)-1]
	}
	
	index := (percentile / 100.0) * float64(len(sortedLatencies))
	
	if index == float64(int(index)) {
		// Exact index
		return sortedLatencies[int(index)-1]
	} else {
		// Interpolate between two values
		lowerIndex := int(index)
		upperIndex := lowerIndex + 1
		
		if upperIndex >= len(sortedLatencies) {
			return sortedLatencies[len(sortedLatencies)-1]
		}
		
		return sortedLatencies[lowerIndex]
	}
}

// Results contains the collected benchmark metrics
type Results struct {
	TotalDuration        time.Duration `json:"total_duration"`
	TotalOperations      int64         `json:"total_operations"`
	Throughput          int64         `json:"throughput"`
	OperationsPerSecond  float64       `json:"operations_per_second"`
	ErrorCount          int           `json:"error_count"`
	AverageLatency      time.Duration `json:"average_latency"`
	P50Latency          time.Duration `json:"p50_latency"`
	P90Latency          time.Duration `json:"p90_latency"`
	P95Latency          time.Duration `json:"p95_latency"`
	P99Latency          time.Duration `json:"p99_latency"`
	P999Latency         time.Duration `json:"p999_latency"`
	MinLatency          time.Duration `json:"min_latency"`
	MaxLatency          time.Duration `json:"max_latency"`
}

// ToMap converts results to a map for easy serialization
func (r *Results) ToMap() map[string]interface{} {
	return map[string]interface{}{
		"total_duration_ms":     r.TotalDuration.Milliseconds(),
		"total_operations":      r.TotalOperations,
		"throughput":           r.Throughput,
		"operations_per_second": r.OperationsPerSecond,
		"error_count":          r.ErrorCount,
		"average_latency_ms":   r.AverageLatency.Milliseconds(),
		"p50_latency_ms":       r.P50Latency.Milliseconds(),
		"p90_latency_ms":       r.P90Latency.Milliseconds(),
		"p95_latency_ms":       r.P95Latency.Milliseconds(),
		"p99_latency_ms":       r.P99Latency.Milliseconds(),
		"p999_latency_ms":      r.P999Latency.Milliseconds(),
		"min_latency_ms":       r.MinLatency.Milliseconds(),
		"max_latency_ms":       r.MaxLatency.Milliseconds(),
	}
}
