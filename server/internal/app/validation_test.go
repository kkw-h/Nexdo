package app

import "testing"

func TestValidateEmail(t *testing.T) {
	t.Parallel()

	cases := []struct {
		name    string
		value   string
		wantErr bool
	}{
		{name: "valid", value: "worker@example.com"},
		{name: "trimmed valid", value: " worker@example.com ", wantErr: false},
		{name: "missing at", value: "worker.example.com", wantErr: true},
		{name: "display name", value: "Worker <worker@example.com>", wantErr: true},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			err := validateEmail(tc.value)
			if tc.wantErr && err == nil {
				t.Fatal("expected error")
			}
			if !tc.wantErr && err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
		})
	}
}

func TestValidateTimezone(t *testing.T) {
	t.Parallel()

	if err := validateTimezone("Asia/Shanghai"); err != nil {
		t.Fatalf("expected valid timezone, got %v", err)
	}
	if err := validateTimezone("Invalid/Timezone"); err == nil {
		t.Fatal("expected invalid timezone error")
	}
}

func TestValidateLocale(t *testing.T) {
	t.Parallel()

	valid := []string{"zh-CN", "en-US", "fr"}
	for _, value := range valid {
		if err := validateLocale(value); err != nil {
			t.Fatalf("expected locale %s to be valid, got %v", value, err)
		}
	}

	invalid := []string{"zh_CN", "123", "en-ABCDEFGHI"}
	for _, value := range invalid {
		if err := validateLocale(value); err == nil {
			t.Fatalf("expected locale %s to be invalid", value)
		}
	}
}

func TestValidateAvatarURL(t *testing.T) {
	t.Parallel()

	valid := []string{"", "https://cdn.nexdo.test/a.png", "http://localhost/avatar.jpg"}
	for _, value := range valid {
		if err := validateAvatarURL(value); err != nil {
			t.Fatalf("expected avatar url %q to be valid, got %v", value, err)
		}
	}

	invalid := []string{"ftp://cdn.nexdo.test/a.png", "/relative/path.png", "not-a-url"}
	for _, value := range invalid {
		if err := validateAvatarURL(value); err == nil {
			t.Fatalf("expected avatar url %q to be invalid", value)
		}
	}
}

func TestValidateRegister(t *testing.T) {
	t.Parallel()

	valid := registerRequest{
		Email:    "worker@example.com",
		Password: "password123",
		Nickname: "worker",
		Timezone: "Asia/Shanghai",
		Locale:   "zh-CN",
	}
	if err := validateRegister(valid); err != nil {
		t.Fatalf("expected valid register request, got %v", err)
	}

	invalid := valid
	invalid.Password = "short"
	if err := validateRegister(invalid); err == nil {
		t.Fatal("expected short password error")
	}
}
