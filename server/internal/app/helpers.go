package app

import (
	"path/filepath"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

func nowISO() string { return time.Now().UTC().Format(time.RFC3339Nano) }
func newID() string  { return uuid.NewString() }

func valueOrDefault[T comparable](value *T, fallback T) T {
	if value == nil {
		return fallback
	}
	return *value
}

func stringOrDefault(value *string, fallback string) string {
	if value == nil {
		return fallback
	}
	return *value
}

func boolOrDefault(value *bool, fallback bool) bool {
	if value == nil {
		return fallback
	}
	return *value
}

func sanitizeFilename(name string) string {
	name = strings.TrimSpace(name)
	if name == "" {
		return "audio.bin"
	}
	var builder strings.Builder
	for _, r := range name {
		if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') || r == '.' || r == '-' || r == '_' {
			builder.WriteRune(r)
		} else {
			builder.WriteByte('_')
		}
	}
	return builder.String()
}

func isAudioUpload(filename, contentType string) bool {
	contentType = strings.TrimSpace(strings.ToLower(contentType))
	if strings.HasPrefix(contentType, "audio/") {
		return true
	}
	if contentType != "" && contentType != "application/octet-stream" {
		return false
	}
	return isAudioExtension(filename)
}

func detectAudioMimeType(filename, contentType string) string {
	contentType = strings.TrimSpace(strings.ToLower(contentType))
	if strings.HasPrefix(contentType, "audio/") {
		return contentType
	}
	switch strings.ToLower(filepath.Ext(filename)) {
	case ".mp3":
		return "audio/mpeg"
	case ".m4a":
		return "audio/mp4"
	case ".aac":
		return "audio/aac"
	case ".wav":
		return "audio/wav"
	case ".ogg", ".oga":
		return "audio/ogg"
	case ".webm":
		return "audio/webm"
	case ".flac":
		return "audio/flac"
	default:
		if contentType != "" {
			return contentType
		}
		return "application/octet-stream"
	}
}

func isAudioExtension(filename string) bool {
	switch strings.ToLower(filepath.Ext(filename)) {
	case ".mp3", ".m4a", ".aac", ".wav", ".ogg", ".oga", ".webm", ".flac":
		return true
	default:
		return false
	}
}

func absoluteURL(c *gin.Context, path string) string {
	base := "http://localhost"
	if c != nil && c.Request != nil && c.Request.URL != nil {
		if c.Request.URL.Scheme != "" && c.Request.URL.Host != "" {
			base = c.Request.URL.Scheme + "://" + c.Request.URL.Host
		} else if c.Request.Host != "" {
			scheme := "http"
			if c.Request.TLS != nil {
				scheme = "https"
			}
			base = scheme + "://" + c.Request.Host
		}
	}
	return base + path
}

func normalizeMultiValueItems(rawValues []string) []string {
	seen := map[string]struct{}{}
	var result []string
	for _, raw := range rawValues {
		for _, item := range strings.Split(raw, ",") {
			item = strings.TrimSpace(item)
			if item == "" {
				continue
			}
			if _, ok := seen[item]; ok {
				continue
			}
			seen[item] = struct{}{}
			result = append(result, item)
		}
	}
	return result
}
