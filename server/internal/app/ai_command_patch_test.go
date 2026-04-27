package app

import "testing"

func TestNormalizeAICommandPatchMapsRepeatAliases(t *testing.T) {
	got := normalizeAICommandPatch(map[string]any{
		"repeat": "每天",
	})

	if got["repeat_rule"] != "daily" {
		t.Fatalf("expected repeat_rule=daily, got %+v", got)
	}
}

func TestNormalizeAICommandPatchMapsRecurrenceAlias(t *testing.T) {
	got := normalizeAICommandPatch(map[string]any{
		"recurrence": "工作日",
	})

	if got["repeat_rule"] != "workday" {
		t.Fatalf("expected repeat_rule=workday, got %+v", got)
	}
}

func TestNormalizeAICommandPatchMapsRepeatRuleChineseValue(t *testing.T) {
	got := normalizeAICommandPatch(map[string]any{
		"repeatRule": "工作日",
	})

	if got["repeat_rule"] != "workday" {
		t.Fatalf("expected repeat_rule=workday, got %+v", got)
	}
}
