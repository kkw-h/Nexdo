package app

import (
	"net/http"
	"strings"
	"testing"
)

func TestListFormCases(t *testing.T) {
	t.Parallel()

	app := newTestApp(t)
	token := registerTestUser(t, app)
	otherToken := registerTestSessionFor(t, app, "resource-other@example.com", "resource-other").AccessToken
	foreignListID := createListForTest(t, app, otherToken, "foreign-list")

	for _, body := range []string{`{"name":"","color_value":1}`, `{"name":"   ","color_value":1}`} {
		rec := performJSON(t, app, http.MethodPost, "/api/v1/lists", token, body)
		if rec.Code != http.StatusBadRequest || !strings.Contains(rec.Body.String(), "name 必填") {
			t.Fatalf("expected create list name validation error, got %d: %s", rec.Code, rec.Body.String())
		}
	}

	createRec := performJSON(t, app, http.MethodPost, "/api/v1/lists", token, `{"name":"工作清单","color_value":3,"sort_order":7}`)
	if createRec.Code != http.StatusCreated {
		t.Fatalf("create list status = %d, body = %s", createRec.Code, createRec.Body.String())
	}
	var created struct {
		Data struct {
			ID         string `json:"id"`
			Name       string `json:"name"`
			ColorValue int    `json:"color_value"`
			SortOrder  int    `json:"sort_order"`
		} `json:"data"`
	}
	decodeBody(t, createRec.Body.Bytes(), &created)
	if created.Data.Name != "工作清单" || created.Data.ColorValue != 3 || created.Data.SortOrder != 7 {
		t.Fatalf("unexpected created list: %+v", created.Data)
	}

	defaultRec := performJSON(t, app, http.MethodPost, "/api/v1/lists", token, `{"name":"默认排序","color_value":1}`)
	if defaultRec.Code != http.StatusCreated {
		t.Fatalf("default list status = %d, body = %s", defaultRec.Code, defaultRec.Body.String())
	}
	var defaults struct {
		Data struct {
			SortOrder int `json:"sort_order"`
		} `json:"data"`
	}
	decodeBody(t, defaultRec.Body.Bytes(), &defaults)
	if defaults.Data.SortOrder != 0 {
		t.Fatalf("expected default sort_order=0, got %+v", defaults.Data)
	}

	blankPatchRec := performJSON(t, app, http.MethodPatch, "/api/v1/lists/"+created.Data.ID, token, `{"name":"   "}`)
	if blankPatchRec.Code != http.StatusBadRequest || !strings.Contains(blankPatchRec.Body.String(), "name 必填") {
		t.Fatalf("expected patch list blank name validation error, got %d: %s", blankPatchRec.Code, blankPatchRec.Body.String())
	}

	patchRec := performJSON(t, app, http.MethodPatch, "/api/v1/lists/"+created.Data.ID, token, `{"name":"工作清单-更新","color_value":8,"sort_order":11}`)
	if patchRec.Code != http.StatusOK {
		t.Fatalf("patch list status = %d, body = %s", patchRec.Code, patchRec.Body.String())
	}
	var patched struct {
		Data struct {
			Name       string `json:"name"`
			ColorValue int    `json:"color_value"`
			SortOrder  int    `json:"sort_order"`
		} `json:"data"`
	}
	decodeBody(t, patchRec.Body.Bytes(), &patched)
	if patched.Data.Name != "工作清单-更新" || patched.Data.ColorValue != 8 || patched.Data.SortOrder != 11 {
		t.Fatalf("unexpected patched list: %+v", patched.Data)
	}

	foreignPatchRec := performJSON(t, app, http.MethodPatch, "/api/v1/lists/"+foreignListID, token, `{"name":"x"}`)
	if foreignPatchRec.Code != http.StatusNotFound {
		t.Fatalf("expected foreign list patch 404, got %d: %s", foreignPatchRec.Code, foreignPatchRec.Body.String())
	}
}

func TestGroupFormCases(t *testing.T) {
	t.Parallel()

	app := newTestApp(t)
	token := registerTestUser(t, app)
	otherToken := registerTestSessionFor(t, app, "group-other@example.com", "group-other").AccessToken
	foreignGroupID := createGroupForTest(t, app, otherToken, "foreign-group")

	for _, body := range []string{`{"name":"","icon_code_point":1}`, `{"name":"   ","icon_code_point":1}`} {
		rec := performJSON(t, app, http.MethodPost, "/api/v1/groups", token, body)
		if rec.Code != http.StatusBadRequest || !strings.Contains(rec.Body.String(), "name 必填") {
			t.Fatalf("expected create group name validation error, got %d: %s", rec.Code, rec.Body.String())
		}
	}

	createRec := performJSON(t, app, http.MethodPost, "/api/v1/groups", token, `{"name":"项目组","icon_code_point":12,"sort_order":4}`)
	if createRec.Code != http.StatusCreated {
		t.Fatalf("create group status = %d, body = %s", createRec.Code, createRec.Body.String())
	}
	var created struct {
		Data struct {
			ID            string `json:"id"`
			Name          string `json:"name"`
			IconCodePoint int    `json:"icon_code_point"`
			SortOrder     int    `json:"sort_order"`
		} `json:"data"`
	}
	decodeBody(t, createRec.Body.Bytes(), &created)
	if created.Data.Name != "项目组" || created.Data.IconCodePoint != 12 || created.Data.SortOrder != 4 {
		t.Fatalf("unexpected created group: %+v", created.Data)
	}

	blankPatchRec := performJSON(t, app, http.MethodPatch, "/api/v1/groups/"+created.Data.ID, token, `{"name":"   "}`)
	if blankPatchRec.Code != http.StatusBadRequest || !strings.Contains(blankPatchRec.Body.String(), "name 必填") {
		t.Fatalf("expected patch group blank name validation error, got %d: %s", blankPatchRec.Code, blankPatchRec.Body.String())
	}

	patchRec := performJSON(t, app, http.MethodPatch, "/api/v1/groups/"+created.Data.ID, token, `{"name":"项目组-更新","icon_code_point":99,"sort_order":10}`)
	if patchRec.Code != http.StatusOK {
		t.Fatalf("patch group status = %d, body = %s", patchRec.Code, patchRec.Body.String())
	}
	var patched struct {
		Data struct {
			Name          string `json:"name"`
			IconCodePoint int    `json:"icon_code_point"`
			SortOrder     int    `json:"sort_order"`
		} `json:"data"`
	}
	decodeBody(t, patchRec.Body.Bytes(), &patched)
	if patched.Data.Name != "项目组-更新" || patched.Data.IconCodePoint != 99 || patched.Data.SortOrder != 10 {
		t.Fatalf("unexpected patched group: %+v", patched.Data)
	}

	foreignPatchRec := performJSON(t, app, http.MethodPatch, "/api/v1/groups/"+foreignGroupID, token, `{"name":"x"}`)
	if foreignPatchRec.Code != http.StatusNotFound {
		t.Fatalf("expected foreign group patch 404, got %d: %s", foreignPatchRec.Code, foreignPatchRec.Body.String())
	}
}

func TestTagFormCases(t *testing.T) {
	t.Parallel()

	app := newTestApp(t)
	token := registerTestUser(t, app)
	otherToken := registerTestSessionFor(t, app, "tag-other@example.com", "tag-other").AccessToken
	foreignTagID := createTagForTest(t, app, otherToken, "foreign-tag")

	for _, body := range []string{`{"name":"","color_value":1}`, `{"name":"   ","color_value":1}`} {
		rec := performJSON(t, app, http.MethodPost, "/api/v1/tags", token, body)
		if rec.Code != http.StatusBadRequest || !strings.Contains(rec.Body.String(), "name 必填") {
			t.Fatalf("expected create tag name validation error, got %d: %s", rec.Code, rec.Body.String())
		}
	}

	createRec := performJSON(t, app, http.MethodPost, "/api/v1/tags", token, `{"name":"标签一","color_value":6}`)
	if createRec.Code != http.StatusCreated {
		t.Fatalf("create tag status = %d, body = %s", createRec.Code, createRec.Body.String())
	}
	var created struct {
		Data struct {
			ID         string `json:"id"`
			Name       string `json:"name"`
			ColorValue int    `json:"color_value"`
		} `json:"data"`
	}
	decodeBody(t, createRec.Body.Bytes(), &created)
	if created.Data.Name != "标签一" || created.Data.ColorValue != 6 {
		t.Fatalf("unexpected created tag: %+v", created.Data)
	}

	blankPatchRec := performJSON(t, app, http.MethodPatch, "/api/v1/tags/"+created.Data.ID, token, `{"name":"   "}`)
	if blankPatchRec.Code != http.StatusBadRequest || !strings.Contains(blankPatchRec.Body.String(), "name 必填") {
		t.Fatalf("expected patch tag blank name validation error, got %d: %s", blankPatchRec.Code, blankPatchRec.Body.String())
	}

	patchRec := performJSON(t, app, http.MethodPatch, "/api/v1/tags/"+created.Data.ID, token, `{"name":"标签一-更新","color_value":9}`)
	if patchRec.Code != http.StatusOK {
		t.Fatalf("patch tag status = %d, body = %s", patchRec.Code, patchRec.Body.String())
	}
	var patched struct {
		Data struct {
			Name       string `json:"name"`
			ColorValue int    `json:"color_value"`
		} `json:"data"`
	}
	decodeBody(t, patchRec.Body.Bytes(), &patched)
	if patched.Data.Name != "标签一-更新" || patched.Data.ColorValue != 9 {
		t.Fatalf("unexpected patched tag: %+v", patched.Data)
	}

	foreignPatchRec := performJSON(t, app, http.MethodPatch, "/api/v1/tags/"+foreignTagID, token, `{"name":"x"}`)
	if foreignPatchRec.Code != http.StatusNotFound {
		t.Fatalf("expected foreign tag patch 404, got %d: %s", foreignPatchRec.Code, foreignPatchRec.Body.String())
	}
}
