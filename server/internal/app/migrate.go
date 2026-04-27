package app

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"strings"

	"gorm.io/gorm"
)

type MigrationResult struct {
	Applied []string
	Skipped []string
}

type schemaMigration struct {
	Version string `gorm:"primaryKey;column:version"`
}

func (schemaMigration) TableName() string {
	return "schema_migrations"
}

func Migrate(databaseURL, dir string) (MigrationResult, error) {
	db, err := openDB(databaseURL)
	if err != nil {
		return MigrationResult{}, err
	}
	return runMigrations(db, dir)
}

func runMigrations(db *gorm.DB, dir string) (MigrationResult, error) {
	dir = resolveMigrationsDir(dir)
	if dir == "" {
		return MigrationResult{}, fmt.Errorf("migrations dir is empty")
	}
	if err := db.AutoMigrate(&schemaMigration{}); err != nil {
		return MigrationResult{}, err
	}

	entries, err := os.ReadDir(dir)
	if err != nil {
		return MigrationResult{}, fmt.Errorf("read migrations dir: %w", err)
	}

	var names []string
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".sql") {
			continue
		}
		names = append(names, entry.Name())
	}
	sort.Strings(names)
	result := MigrationResult{}

	for _, name := range names {
		var count int64
		if err := db.Model(&schemaMigration{}).Where("version = ?", name).Count(&count).Error; err != nil {
			return MigrationResult{}, err
		}
		if count > 0 {
			result.Skipped = append(result.Skipped, name)
			continue
		}

		content, err := os.ReadFile(filepath.Join(dir, name))
		if err != nil {
			return MigrationResult{}, fmt.Errorf("read migration %s: %w", name, err)
		}

		if err := db.Transaction(func(tx *gorm.DB) error {
			if err := tx.Exec(string(content)).Error; err != nil {
				return fmt.Errorf("exec migration %s: %w", name, err)
			}
			return tx.Create(&schemaMigration{Version: name}).Error
		}); err != nil {
			return MigrationResult{}, err
		}
		result.Applied = append(result.Applied, name)
	}

	return result, nil
}

func resolveMigrationsDir(dir string) string {
	if dir != "" {
		return dir
	}
	_, filename, _, ok := runtime.Caller(0)
	if !ok {
		return ""
	}
	return filepath.Clean(filepath.Join(filepath.Dir(filename), "..", "..", "migrations"))
}
