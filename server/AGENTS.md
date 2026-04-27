# Repository Guidelines

## Project Structure & Module Organization

This repository is a Go API service for Nexdo. Main entrypoints live in `cmd/`: `cmd/api` starts the HTTP server and `cmd/migrate` runs SQL migrations. Core application code is under `internal/`, with `internal/app` holding handlers, services, repositories, sync helpers, and OpenAPI output. Shared configuration is in `internal/config`, response helpers in `internal/http/response`, domain models in `internal/models`, and utility packages in `internal/pkg`.

Database migrations are stored in `migrations/*.sql`. Project docs live in `docs/`. Tests currently focus on API behavior and are mainly in `internal/app/app_test.go`.

## Build, Test, and Development Commands

- `go run ./cmd/api`: start the API locally on `APP_ADDR` or `:8080`.
- `go run ./cmd/migrate`: apply pending SQL migrations without starting the server.
- `go test ./...`: run the full test suite.
- `go build ./cmd/api`: compile the API binary.
- `docker compose up -d --build`: start the API and PostgreSQL using the included compose file.

Set `DATABASE_URL` for SQLite or PostgreSQL. Example: `DATABASE_URL='sqlite://file:nexdo.db?_foreign_keys=on' go run ./cmd/api`.

## Coding Style & Naming Conventions

Follow standard Go formatting and idioms. Run `gofmt` on changed files before submitting. Use tabs for indentation as produced by Go tooling. Keep package names short and lowercase. Exported identifiers use `PascalCase`; unexported helpers use `camelCase`.

Match the existing layering:
- handlers decode requests and write responses
- services enforce business rules
- repositories perform database access

Prefer descriptive file names such as `auth_service.go`, `reminder_repository.go`, and `quicknote_handlers.go`.

## Testing Guidelines

Write table-driven tests where behavior branches by input. Name tests with `Test...` and keep them close to the feature area, following the pattern in `internal/app/app_test.go`. Cover API status codes, response payloads, and persistence side effects for new endpoints or migrations.

Run `go test ./...` before opening a PR.

## Commit & Pull Request Guidelines

Recent history uses short, imperative commit messages such as `Fix recurring reminder timezone rollover` and `Initial Go API implementation`. Keep the same style: concise, capitalized, and behavior-focused.

PRs should explain the change, note any schema or environment variable updates, and include sample requests or responses when API behavior changes. Link the related issue if one exists.

## Security & Configuration Tips

Do not commit real secrets. Override `JWT_ACCESS_SECRET` and `JWT_REFRESH_SECRET` outside local development. Review `AUTO_MIGRATE` carefully in shared environments, and keep migration files ordered and append-only.
