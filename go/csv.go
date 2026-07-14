package emay

import (
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"
)

// CSVResult holds the parsed readings and any warnings.
type CSVResult struct {
	Readings []Reading
	Warnings []string
}

// DSTFoldCorrector restores physical time across DST fall-back transitions.
type DSTFoldCorrector struct {
	offset   float64
	previous *float64
}

func NewDSTFoldCorrector() *DSTFoldCorrector {
	return &DSTFoldCorrector{}
}

func (c *DSTFoldCorrector) Corrected(parsed time.Time) time.Time {
	secs := float64(parsed.Unix())
	if c.previous == nil {
		c.previous = &secs
		return parsed
	}

	if c.offset > 0 && secs >= *c.previous {
		c.offset = 0
	}

	candidate := secs + c.offset
	delta := candidate - *c.previous

	if delta < -5 && delta >= -7200 {
		c.offset += 3600
		candidate = secs + c.offset
	}

	c.previous = &candidate
	return time.Unix(int64(candidate), 0)
}

// ParseCSV parses EMAY CSV content.
func ParseCSV(content string, correctDST bool) (*CSVResult, error) {
	lines := []string{}
	for _, l := range strings.Split(content, "\n") {
		l = strings.TrimSpace(l)
		if l != "" { lines = append(lines, l) }
	}
	if len(lines) <= 1 {
		return nil, fmt.Errorf("CSV file contains no data rows")
	}

	result := &CSVResult{}
	var corrector *DSTFoldCorrector
	if correctDST { corrector = NewDSTFoldCorrector() }

	// Parse date format: M/d/yyyy h:mm:ss a
	layout := "1/2/2006 3:04:05 PM"

	for i := 1; i < len(lines); i++ {
		rowNum := i + 1
		fields := strings.Split(lines[i], ",")
		for j := range fields { fields[j] = strings.TrimSpace(fields[j]) }
		if len(fields) < 2 {
			result.Warnings = append(result.Warnings, fmt.Sprintf("Row %d: skipping", rowNum))
			continue
		}

		dateStr := fields[0] + " " + fields[1]
		parsed, err := time.ParseInLocation(layout, dateStr, time.Local)
		if err != nil {
			result.Warnings = append(result.Warnings, fmt.Sprintf("Row %d: invalid date '%s'", rowNum, dateStr))
			continue
		}

		if corrector != nil { parsed = corrector.Corrected(parsed) }

		var spo2, pulse *int
		if len(fields) > 2 && fields[2] != "" {
			if v, err := strconv.Atoi(fields[2]); err == nil { spo2 = &v }
		}
		if len(fields) > 3 && fields[3] != "" {
			if v, err := strconv.Atoi(fields[3]); err == nil { pulse = &v }
		}

		result.Readings = append(result.Readings, Reading{SpO2: spo2, Pulse: pulse, Timestamp: parsed})
	}

	return result, nil
}

// ParseCSVFile parses an EMAY CSV file from disk.
func ParseCSVFile(path string, correctDST bool) (*CSVResult, error) {
	data, err := os.ReadFile(path)
	if err != nil { return nil, err }
	return ParseCSV(string(data), correctDST)
}
