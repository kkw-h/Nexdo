package app

import (
	"net/http"
	"strings"
	"testing"
)

func TestAuthRegisterAndLoginValidationCases(t *testing.T) {
	t.Parallel()

	app := newTestApp(t)

	cases := []struct {
		name string
		body string
		want string
	}{
		{
			name: "invalid email",
			body: `{"email":"invalid","password":"password123","nickname":"worker","timezone":"Asia/Shanghai","locale":"zh-CN"}`,
			want: "email 格式不正确",
		},
		{
			name: "short password",
			body: `{"email":"worker@example.com","password":"short","nickname":"worker","timezone":"Asia/Shanghai","locale":"zh-CN"}`,
			want: "password 长度不能少于 8",
		},
		{
			name: "blank profile fields",
			body: `{"email":"worker@example.com","password":"password123","nickname":"   ","timezone":"Asia/Shanghai","locale":"zh-CN"}`,
			want: "nickname、timezone、locale 必填",
		},
		{
			name: "invalid timezone",
			body: `{"email":"worker@example.com","password":"password123","nickname":"worker","timezone":"Invalid/Timezone","locale":"zh-CN"}`,
			want: "timezone 不合法",
		},
		{
			name: "invalid locale",
			body: `{"email":"worker@example.com","password":"password123","nickname":"worker","timezone":"Asia/Shanghai","locale":"zh_CN"}`,
			want: "locale 不合法",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			rec := performJSON(t, app, http.MethodPost, "/api/v1/auth/register", "", tc.body)
			if rec.Code != http.StatusBadRequest || !strings.Contains(rec.Body.String(), tc.want) {
				t.Fatalf("expected register validation %q, got %d: %s", tc.want, rec.Code, rec.Body.String())
			}
		})
	}

	loginRec := performJSON(t, app, http.MethodPost, "/api/v1/auth/login", "", `{"email":"","password":"password123"}`)
	if loginRec.Code != http.StatusBadRequest || !strings.Contains(loginRec.Body.String(), "email 和 password 必填") {
		t.Fatalf("expected login required field error, got %d: %s", loginRec.Code, loginRec.Body.String())
	}
}

func TestAuthProfileAndPasswordFormCases(t *testing.T) {
	t.Parallel()

	app := newTestApp(t)
	session := registerTestSessionFor(t, app, "profile-form@example.com", "profile-form")

	updateRec := performJSON(t, app, http.MethodPatch, "/api/v1/me", session.AccessToken, `{
		"nickname":"  表单用户  ",
		"avatar_url":"https://cdn.nexdo.test/avatar.png",
		"timezone":"Asia/Tokyo",
		"locale":"ja-JP"
	}`)
	if updateRec.Code != http.StatusOK {
		t.Fatalf("update profile status = %d, body = %s", updateRec.Code, updateRec.Body.String())
	}
	var updated struct {
		Data struct {
			Nickname  string `json:"nickname"`
			AvatarURL string `json:"avatar_url"`
			Timezone  string `json:"timezone"`
			Locale    string `json:"locale"`
		} `json:"data"`
	}
	decodeBody(t, updateRec.Body.Bytes(), &updated)
	if updated.Data.Nickname != "表单用户" || updated.Data.AvatarURL != "https://cdn.nexdo.test/avatar.png" || updated.Data.Timezone != "Asia/Tokyo" || updated.Data.Locale != "ja-JP" {
		t.Fatalf("unexpected updated profile: %+v", updated.Data)
	}

	for _, tc := range []struct {
		name string
		body string
		want string
	}{
		{name: "invalid avatar", body: `{"avatar_url":"ftp://bad.test/avatar.png"}`, want: "avatar_url 必须是 http 或 https URL"},
		{name: "invalid timezone", body: `{"timezone":"Bad/Timezone"}`, want: "timezone 不合法"},
		{name: "invalid locale", body: `{"locale":"zh_CN"}`, want: "locale 不合法"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			rec := performJSON(t, app, http.MethodPatch, "/api/v1/me", session.AccessToken, tc.body)
			if rec.Code != http.StatusBadRequest || !strings.Contains(rec.Body.String(), tc.want) {
				t.Fatalf("expected profile validation %q, got %d: %s", tc.want, rec.Code, rec.Body.String())
			}
		})
	}

	shortPasswordRec := performJSON(t, app, http.MethodPatch, "/api/v1/me/password", session.AccessToken, `{
		"old_password":"password123",
		"new_password":"short"
	}`)
	if shortPasswordRec.Code != http.StatusBadRequest || !strings.Contains(shortPasswordRec.Body.String(), "new_password 长度不能少于 8") {
		t.Fatalf("expected short password error, got %d: %s", shortPasswordRec.Code, shortPasswordRec.Body.String())
	}

	wrongOldPasswordRec := performJSON(t, app, http.MethodPatch, "/api/v1/me/password", session.AccessToken, `{
		"old_password":"wrong-password",
		"new_password":"new-password-123"
	}`)
	if wrongOldPasswordRec.Code != http.StatusUnauthorized || !strings.Contains(wrongOldPasswordRec.Body.String(), "旧密码不正确") {
		t.Fatalf("expected wrong old password error, got %d: %s", wrongOldPasswordRec.Code, wrongOldPasswordRec.Body.String())
	}
}

func TestAuthDeleteDeviceNotFound(t *testing.T) {
	t.Parallel()

	app := newTestApp(t)
	session := registerTestSessionFor(t, app, "device-form@example.com", "device-form")

	rec := performJSON(t, app, http.MethodDelete, "/api/v1/me/devices/"+newID(), session.AccessToken, "")
	if rec.Code != http.StatusNotFound || !strings.Contains(rec.Body.String(), "设备不存在") {
		t.Fatalf("expected delete device not found, got %d: %s", rec.Code, rec.Body.String())
	}
}
