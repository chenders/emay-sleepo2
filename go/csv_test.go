package emay

import (
	"testing"
)

func TestParseCSVValid(t *testing.T) {
	csv := "Date,Time,SpO2(%),PR(bpm)\n5/8/2026,4:46:58 PM,98,52\n5/8/2026,4:47:00 PM,,58"
	result, err := ParseCSV(csv, false)
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Readings) != 2 {
		t.Errorf("expected 2, got %d", len(result.Readings))
	}
	if *result.Readings[0].SpO2 != 98 {
		t.Error("first spo2 should be 98")
	}
	if *result.Readings[0].Pulse != 52 {
		t.Error("first pulse should be 52")
	}
	if result.Readings[1].SpO2 != nil {
		t.Error("second spo2 should be nil")
	}
	if *result.Readings[1].Pulse != 58 {
		t.Error("second pulse should be 58")
	}
}

func TestParseCSVEmpty(t *testing.T) {
	_, err := ParseCSV("Date,Time,SpO2(%),PR(bpm)", false)
	if err == nil {
		t.Error("expected error for empty CSV")
	}
}

func TestParseCSVInvalidDate(t *testing.T) {
	csv := "Date,Time,SpO2(%),PR(bpm)\nbad,data,99,50\n5/8/2026,4:47:00 PM,98,52"
	result, err := ParseCSV(csv, false)
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Warnings) < 1 {
		t.Error("expected warnings")
	}
	if len(result.Readings) != 1 {
		t.Errorf("expected 1, got %d", len(result.Readings))
	}
}
