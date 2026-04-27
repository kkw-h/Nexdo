package app

import (
	"net/mail"
	neturl "net/url"
	"regexp"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

var localePattern = regexp.MustCompile(`^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$`)

func decodeJSON(c *gin.Context, dst any) error {
	if err := c.ShouldBindJSON(dst); err != nil {
		return badRequest("请求体必须是合法 JSON")
	}
	return nil
}

func validateRegister(req registerRequest) error {
	if err := validateEmail(req.Email); err != nil {
		return err
	}
	if len(req.Password) < 8 {
		return badRequest("password 长度不能少于 8")
	}
	if strings.TrimSpace(req.Nickname) == "" || strings.TrimSpace(req.Timezone) == "" || strings.TrimSpace(req.Locale) == "" {
		return badRequest("nickname、timezone、locale 必填")
	}
	if err := validateTimezone(req.Timezone); err != nil {
		return err
	}
	if err := validateLocale(req.Locale); err != nil {
		return err
	}
	return nil
}

func validateReminderPayload(req reminderPayload) error {
	if strings.TrimSpace(req.Title) == "" {
		return badRequest("title 必填")
	}
	if _, err := parseRFC3339Time(req.DueAt); err != nil {
		return badRequest("due_at 必须是 RFC3339 时间戳")
	}
	if strings.TrimSpace(req.ListID) == "" || strings.TrimSpace(req.GroupID) == "" {
		return badRequest("list_id 和 group_id 必填")
	}
	if _, err := validateRepeatRule(stringOrDefault(req.RepeatRule, "none")); err != nil {
		return badRequest("repeat_rule 不合法")
	}
	if _, err := validateReminderSchedule(req.DueAt, req.RepeatRule, req.RepeatUntilAt, req.RemindBeforeMinutes); err != nil {
		return err
	}
	return nil
}

func parseBooleanQuery(value, field string) (bool, error) {
	switch value {
	case "true", "1":
		return true, nil
	case "false", "0":
		return false, nil
	default:
		return false, badRequest(field + " 必须是 true/false/1/0")
	}
}

func parseMultiValueQuery(c *gin.Context, field string) []string {
	rawValues := c.QueryArray(field)
	if len(rawValues) == 0 {
		if single := c.Query(field); single != "" {
			rawValues = []string{single}
		}
	}
	return normalizeMultiValueItems(rawValues)
}

func parseMultiValueQueryProvider(c queryProvider, field string) []string {
	rawValues := c.QueryArray(field)
	if len(rawValues) == 0 {
		if single := c.Query(field); single != "" {
			rawValues = []string{single}
		}
	}
	return normalizeMultiValueItems(rawValues)
}

func normalizeRepeatRule(rule string) string {
	switch rule {
	case "none", "daily", "weekly", "monthly", "yearly", "workday", "non_workday":
		return rule
	default:
		return "none"
	}
}

func validateRepeatRule(rule string) (string, error) {
	rule = strings.TrimSpace(rule)
	if rule == "" {
		return "none", nil
	}
	normalized := normalizeRepeatRule(rule)
	if normalized == "none" && rule != "none" {
		return "", badRequest("repeat_rule 不合法")
	}
	return normalized, nil
}

func validateReminderSchedule(dueAt string, repeatRule *string, repeatUntilAt *string, remindBeforeMinutes *int) (string, error) {
	rule, err := validateRepeatRule(stringOrDefault(repeatRule, "none"))
	if err != nil {
		return "", badRequest("repeat_rule 不合法")
	}
	dueTS, err := parseRFC3339Time(dueAt)
	if err != nil {
		return "", badRequest("due_at 必须是 RFC3339 时间戳")
	}
	if repeatUntilAt != nil && strings.TrimSpace(*repeatUntilAt) != "" {
		repeatUntilTS, err := parseRFC3339Time(*repeatUntilAt)
		if err != nil {
			return "", badRequest("repeat_until_at 必须是 RFC3339 时间戳")
		}
		if rule != "none" && repeatUntilTS.UTC().Before(dueTS.UTC()) {
			return "", badRequest("repeat_until_at 不能早于 due_at")
		}
	}
	if remindBeforeMinutes != nil && *remindBeforeMinutes < 0 {
		return "", badRequest("remind_before_minutes 不能小于 0")
	}
	return rule, nil
}

func validateEmail(value string) error {
	value = strings.TrimSpace(value)
	addr, err := mail.ParseAddress(value)
	if err != nil || addr.Address != value {
		return badRequest("email 格式不正确")
	}
	return nil
}

func validateTimezone(value string) error {
	value = strings.TrimSpace(value)
	if value == "" {
		return badRequest("timezone 必填")
	}
	if _, err := time.LoadLocation(value); err != nil {
		return badRequest("timezone 不合法")
	}
	return nil
}

func validateLocale(value string) error {
	value = strings.TrimSpace(value)
	if value == "" {
		return badRequest("locale 必填")
	}
	if !localePattern.MatchString(value) {
		return badRequest("locale 不合法")
	}
	return nil
}

func validateAvatarURL(value string) error {
	value = strings.TrimSpace(value)
	if value == "" {
		return nil
	}
	parsed, err := neturl.Parse(value)
	if err != nil || parsed.Host == "" {
		return badRequest("avatar_url 必须是合法 URL")
	}
	if parsed.Scheme != "http" && parsed.Scheme != "https" {
		return badRequest("avatar_url 必须是 http 或 https URL")
	}
	return nil
}
