package main

import (
	"log"

	"nexdo-server-golang/internal/app"
	"nexdo-server-golang/internal/config"
)

func main() {
	cfg := config.Load()

	result, err := app.Migrate(cfg.DatabaseURL, cfg.MigrationsDir)
	if err != nil {
		log.Fatalf("run migrations: %v", err)
	}

	log.Printf("migrations complete: applied=%d skipped=%d", len(result.Applied), len(result.Skipped))
	for _, name := range result.Applied {
		log.Printf("applied migration: %s", name)
	}
	for _, name := range result.Skipped {
		log.Printf("skipped migration: %s", name)
	}
}
