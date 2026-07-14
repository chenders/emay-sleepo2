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
//
// On the night clocks fall back, the 1:00–2:00 AM hour repeats — producing
// duplicate wall-clock timestamps. Without correction, the repeated hour's
// samples collide in deduplication and an hour of real data silently vanishes.
//
// Algorithm: When a backward jump of 5–7200 seconds is detected, cross-check
// whether the local timezone actually transitioned. If yes, add 3600 seconds
// of correction. A backward jump with NO nearby DST transition (device-clock
// resync or manual time change) is left untouched.
type DSTFoldCorrector struct {
	offset   time.Duration
	previous time.Time
	hasPrev  bool
	loc      *time.Location
}

func NewDSTFoldCorrector() *DSTFoldCorrector {
	return &DSTFoldCorrector{loc: time.Local}
}

func (c *DSTFoldCorrector) Corrected(parsed time.Time) time.Time {
	if !c.hasPrev {
		c.previous = parsed
		c.hasPrev = true
		return parsed
	}

	// Once the naive parse catches back up to the corrected timeline,
	// wall clock has passed the ambiguous hour — stop compensating.
	if c.offset > 0 && !parsed.Before(c.previous) {
		c.offset = 0
	}

	candidate := parsed.Add(c.offset)
	delta := candidate.Sub(c.previous).Seconds()

	if delta < -5 && delta >= -7200 && c.locFellBack(parsed) {
		c.offset += 3600 * time.Second
		candidate = parsed.Add(c.offset)
	}

	c.previous = candidate
	return candidate
}

// locFellBack returns true if the local timezone actually transitioned
// clocks back within ±2h of instant. A device-clock resync or manually
// adjusted time regresses the wall clock with no transition anywhere
// near — left untouched.
func (c *DSTFoldCorrector) locFellBack(instant time.Time) bool {
	searchStart := instant.Add(-2 * time.Hour)
	searchEnd := instant.Add(2 * time.Hour)
	cur := searchStart
	for !cur.After(searchEnd) {
		_, after := cur.Zone()
		_, afterNext := cur.Add(1*time.Second).Zone()
		// Transition occurred if the offset changed
		if after != afterNext {
			return afterNext < after
		}
		cur = cur.Add(1 * time.Minute)
	}
	return false
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
