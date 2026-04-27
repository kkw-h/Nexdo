package app

import (
	"net/http"
	"strings"
	"testing"
)

func TestQuickNoteJSONFormValidationAndDefaults(t *testing.T) {
	t.Parallel()

	app := newTestApp(t)
	token := registerTestUser(t, app)

	for _, body := range []string{`{"content":""}`, `{"content":"   "}`} {
		rec := performJSON(t, app, http.MethodPost, "/api/v1/quick-notes", token, body)
		if rec.Code != http.StatusBadRequest || !strings.Contains(rec.Body.String(), "content 必填") {
			t.Fatalf("expected quick note content validation error, got %d: %s", rec.Code, rec.Body.String())
		}
	}

	fullRec := performJSON(t, app, http.MethodPost, "/api/v1/quick-notes", token, `{"content":"  带波形闪念  ","waveform_samples":[1,2,3,5]}`)
	if fullRec.Code != http.StatusCreated {
		t.Fatalf("create quick note status = %d, body = %s", fullRec.Code, fullRec.Body.String())
	}
	var full struct {
		Data struct {
			ID              string `json:"id"`
			Content         string `json:"content"`
			Status          string `json:"status"`
			WaveformSamples []int  `json:"waveform_samples"`
		} `json:"data"`
	}
	decodeBody(t, fullRec.Body.Bytes(), &full)
	if full.Data.Content != "带波形闪念" || full.Data.Status != "draft" {
		t.Fatalf("unexpected created quick note: %+v", full.Data)
	}
	if len(full.Data.WaveformSamples) != 4 || full.Data.WaveformSamples[3] != 5 {
		t.Fatalf("unexpected waveform samples: %+v", full.Data.WaveformSamples)
	}

	defaultRec := performJSON(t, app, http.MethodPost, "/api/v1/quick-notes", token, `{"content":"纯文本闪念"}`)
	if defaultRec.Code != http.StatusCreated {
		t.Fatalf("default quick note status = %d, body = %s", defaultRec.Code, defaultRec.Body.String())
	}
	var defaults struct {
		Data struct {
			Content         string `json:"content"`
			Status          string `json:"status"`
			WaveformSamples []int  `json:"waveform_samples"`
		} `json:"data"`
	}
	decodeBody(t, defaultRec.Body.Bytes(), &defaults)
	if defaults.Data.Content != "纯文本闪念" || defaults.Data.Status != "draft" {
		t.Fatalf("unexpected default quick note: %+v", defaults.Data)
	}
	if len(defaults.Data.WaveformSamples) != 0 {
		t.Fatalf("expected empty waveform by default, got %+v", defaults.Data.WaveformSamples)
	}
}

func TestQuickNotePatchFormCases(t *testing.T) {
	t.Parallel()

	app := newTestApp(t)
	token := registerTestUser(t, app)

	createRec := performJSON(t, app, http.MethodPost, "/api/v1/quick-notes", token, `{"content":"待更新闪念","waveform_samples":[8,6,4]}`)
	if createRec.Code != http.StatusCreated {
		t.Fatalf("create quick note status = %d, body = %s", createRec.Code, createRec.Body.String())
	}
	var created struct {
		Data struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	decodeBody(t, createRec.Body.Bytes(), &created)

	blankContentRec := performJSON(t, app, http.MethodPatch, "/api/v1/quick-notes/"+created.Data.ID, token, `{"content":"   "}`)
	if blankContentRec.Code != http.StatusBadRequest || !strings.Contains(blankContentRec.Body.String(), "content 必填") {
		t.Fatalf("expected blank quick note content validation error, got %d: %s", blankContentRec.Code, blankContentRec.Body.String())
	}

	invalidStatusRec := performJSON(t, app, http.MethodPatch, "/api/v1/quick-notes/"+created.Data.ID, token, `{"status":"archived"}`)
	if invalidStatusRec.Code != http.StatusBadRequest || !strings.Contains(invalidStatusRec.Body.String(), "status 只能是 draft 或 converted") {
		t.Fatalf("expected invalid status error, got %d: %s", invalidStatusRec.Code, invalidStatusRec.Body.String())
	}

	patchRec := performJSON(t, app, http.MethodPatch, "/api/v1/quick-notes/"+created.Data.ID, token, `{"content":"  已更新闪念  ","waveform_samples":[]}`)
	if patchRec.Code != http.StatusOK {
		t.Fatalf("patch quick note status = %d, body = %s", patchRec.Code, patchRec.Body.String())
	}
	var patched struct {
		Data struct {
			Content         string `json:"content"`
			Status          string `json:"status"`
			WaveformSamples []int  `json:"waveform_samples"`
		} `json:"data"`
	}
	decodeBody(t, patchRec.Body.Bytes(), &patched)
	if patched.Data.Content != "已更新闪念" || patched.Data.Status != "draft" {
		t.Fatalf("unexpected patched quick note: %+v", patched.Data)
	}
	if len(patched.Data.WaveformSamples) != 0 {
		t.Fatalf("expected cleared waveform samples, got %+v", patched.Data.WaveformSamples)
	}

	listRec := performJSON(t, app, http.MethodGet, "/api/v1/quick-notes", token, "")
	if listRec.Code != http.StatusOK {
		t.Fatalf("list quick notes status = %d, body = %s", listRec.Code, listRec.Body.String())
	}
	var listed struct {
		Data []struct {
			ID              string `json:"id"`
			Content         string `json:"content"`
			WaveformSamples []int  `json:"waveform_samples"`
		} `json:"data"`
	}
	decodeBody(t, listRec.Body.Bytes(), &listed)
	if len(listed.Data) == 0 || listed.Data[0].ID != created.Data.ID || listed.Data[0].Content != "已更新闪念" {
		t.Fatalf("unexpected listed quick notes: %+v", listed.Data)
	}
	if len(listed.Data[0].WaveformSamples) != 0 {
		t.Fatalf("expected stored waveform samples to be cleared, got %+v", listed.Data[0].WaveformSamples)
	}
}
