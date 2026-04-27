package app

import "testing"

func TestBuildReminderAliasesAddsCommonSemanticVariants(t *testing.T) {
	got := buildReminderAliases("去公司吃饭")

	expected := []string{
		"上班",
		"去公司",
		"回公司",
		"到公司",
		"公司",
		"吃饭",
		"用餐",
	}

	for _, item := range expected {
		if !containsString(got, item) {
			t.Fatalf("expected alias %q in %+v", item, got)
		}
	}
}

func containsString(items []string, want string) bool {
	for _, item := range items {
		if item == want {
			return true
		}
	}
	return false
}
