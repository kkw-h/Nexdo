package app

import (
	"fmt"
	"time"
)

var officialHolidays = map[int][]string{
	2025: {
		"2025-01-01", "2025-01-28", "2025-01-29", "2025-01-30", "2025-01-31", "2025-02-01", "2025-02-02",
		"2025-02-03", "2025-02-04", "2025-04-04", "2025-04-05", "2025-04-06", "2025-05-01", "2025-05-02",
		"2025-05-03", "2025-05-04", "2025-05-05", "2025-05-31", "2025-06-01", "2025-06-02", "2025-10-01",
		"2025-10-02", "2025-10-03", "2025-10-04", "2025-10-05", "2025-10-06", "2025-10-07", "2025-10-08",
	},
	2026: {
		"2026-01-01", "2026-01-02", "2026-01-03", "2026-02-15", "2026-02-16", "2026-02-17", "2026-02-18",
		"2026-02-19", "2026-02-20", "2026-02-21", "2026-02-22", "2026-02-23", "2026-04-04", "2026-04-05",
		"2026-04-06", "2026-05-01", "2026-05-02", "2026-05-03", "2026-05-04", "2026-05-05", "2026-06-19",
		"2026-06-20", "2026-06-21", "2026-09-25", "2026-09-26", "2026-09-27", "2026-10-01", "2026-10-02",
		"2026-10-03", "2026-10-04", "2026-10-05", "2026-10-06", "2026-10-07",
	},
}

var adjustedWorkdays = map[int][]string{
	2025: {"2025-01-26", "2025-02-08", "2025-04-27", "2025-09-28", "2025-10-11"},
	2026: {"2026-01-04", "2026-02-14", "2026-02-28", "2026-05-09", "2026-09-20", "2026-10-10"},
}

func nextDate(rule, dueAt string) (string, error) {
	if rule == "workday" || rule == "non_workday" {
		ts, err := parseRFC3339Time(dueAt)
		if err != nil {
			return "", fmt.Errorf("due_at 必须是 RFC3339 时间戳")
		}
		nextDateOnly, err := nextChinaCalendarDate(ts.Format("2006-01-02"), func(candidate string) bool {
			if rule == "workday" {
				return isChinaWorkday(candidate)
			}
			return isChinaNonWorkday(candidate)
		})
		if err != nil {
			return "", err
		}
		day, _ := time.Parse("2006-01-02", nextDateOnly)
		next := time.Date(day.Year(), day.Month(), day.Day(), ts.Hour(), ts.Minute(), ts.Second(), ts.Nanosecond(), ts.Location())
		return next.Format(time.RFC3339Nano), nil
	}

	ts, err := parseRFC3339Time(dueAt)
	if err != nil {
		return "", fmt.Errorf("due_at 必须是 RFC3339 时间戳")
	}

	switch rule {
	case "daily":
		ts = ts.AddDate(0, 0, 1)
	case "weekly":
		ts = ts.AddDate(0, 0, 7)
	case "monthly":
		ts = ts.AddDate(0, 1, 0)
	case "yearly":
		ts = ts.AddDate(1, 0, 0)
	}
	return ts.Format(time.RFC3339Nano), nil
}

func parseRFC3339Time(value string) (time.Time, error) {
	ts, err := time.Parse(time.RFC3339Nano, value)
	if err == nil {
		return ts, nil
	}
	return time.Parse(time.RFC3339, value)
}

func isChinaWorkday(dateOnly string) bool {
	if containsDate(adjustedWorkdays, dateOnly) {
		return true
	}
	if containsDate(officialHolidays, dateOnly) {
		return false
	}
	return !isWeekend(dateOnly)
}

func isChinaNonWorkday(dateOnly string) bool {
	return !isChinaWorkday(dateOnly)
}

func nextChinaCalendarDate(dateOnly string, matcher func(candidate string) bool) (string, error) {
	current, err := time.Parse("2006-01-02", dateOnly)
	if err != nil {
		return "", err
	}
	for i := 0; i < 370; i++ {
		current = current.AddDate(0, 0, 1)
		candidate := current.Format("2006-01-02")
		if matcher(candidate) {
			return candidate, nil
		}
	}
	return "", fmt.Errorf("中国节假日日历超出支持范围")
}

func containsDate(source map[int][]string, dateOnly string) bool {
	for _, values := range source {
		for _, value := range values {
			if value == dateOnly {
				return true
			}
		}
	}
	return false
}

func isWeekend(dateOnly string) bool {
	date, err := time.Parse("2006-01-02", dateOnly)
	if err != nil {
		return false
	}
	weekday := date.Weekday()
	return weekday == time.Saturday || weekday == time.Sunday
}
