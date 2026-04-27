package config

import (
	"os"
	"path/filepath"
	"runtime"
	"strconv"
	"time"
)

type Config struct {
	AppEnv            string
	AppName           string
	Addr              string
	DatabaseURL       string
	AIServiceBaseURL  string
	AIServiceTimeout  time.Duration
	AIConfirmTTL      time.Duration
	JWTAccessSecret   string
	JWTRefreshSecret  string
	AccessTokenTTL    time.Duration
	RefreshTokenTTL   time.Duration
	AudioStorageDir   string
	EnableAutoMigrate bool
	MigrationsDir     string
}

func Load() Config {
	return Config{
		AppEnv:            getenv("APP_ENV", "development"),
		AppName:           getenv("APP_NAME", "nexdo-server"),
		Addr:              getenv("APP_ADDR", ":8080"),
		DatabaseURL:       getenv("DATABASE_URL", "sqlite://file:nexdo.db?_foreign_keys=on"),
		AIServiceBaseURL:  getenv("AI_SERVICE_BASE_URL", "http://localhost:3030"),
		AIServiceTimeout:  getDuration("AI_SERVICE_TIMEOUT_SECONDS", 60),
		AIConfirmTTL:      getDuration("AI_CONFIRM_TTL_SECONDS", 600),
		JWTAccessSecret:   getenv("JWT_ACCESS_SECRET", "dev-access-secret"),
		JWTRefreshSecret:  getenv("JWT_REFRESH_SECRET", "dev-refresh-secret"),
		AccessTokenTTL:    getDuration("JWT_ACCESS_TTL_SECONDS", 3600),
		RefreshTokenTTL:   getDuration("JWT_REFRESH_TTL_SECONDS", 2592000),
		AudioStorageDir:   getenv("AUDIO_STORAGE_DIR", "storage/audio"),
		EnableAutoMigrate: getenv("AUTO_MIGRATE", "true") == "true",
		MigrationsDir:     getenv("MIGRATIONS_DIR", defaultMigrationsDir()),
	}
}

func getenv(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}

func getDuration(key string, fallbackSeconds int) time.Duration {
	raw := getenv(key, "")
	if raw == "" {
		return time.Duration(fallbackSeconds) * time.Second
	}
	value, err := strconv.Atoi(raw)
	if err != nil || value <= 0 {
		return time.Duration(fallbackSeconds) * time.Second
	}
	return time.Duration(value) * time.Second
}

func defaultMigrationsDir() string {
	_, filename, _, ok := runtime.Caller(0)
	if !ok {
		return "migrations"
	}
	return filepath.Clean(filepath.Join(filepath.Dir(filename), "..", "..", "migrations"))
}
