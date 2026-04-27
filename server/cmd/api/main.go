package main

import (
	"log"

	"nexdo-server-golang/internal/app"
	"nexdo-server-golang/internal/config"
)

func main() {
	cfg := config.Load()
	application, err := app.New(cfg)
	if err != nil {
		log.Fatalf("bootstrap app: %v", err)
	}

	if err := application.Run(); err != nil {
		log.Fatalf("run app: %v", err)
	}
}
