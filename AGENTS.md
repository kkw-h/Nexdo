# Repository Guidelines

## Project Structure & Module Organization
The repository is organized as a monorepo. The Flutter frontend lives in `app/`, with entrypoint `app/lib/main.dart` bootstrapping `app/lib/src/app.dart` and the feature-based tree under `app/lib/src/features/<feature>/{data,domain,presentation}` (e.g., `auth` and `reminders`)—follow this layering when adding flows. Frontend tests mirror the source layout inside `app/test/…`; create `app/test/features/<feature>/*_test.dart` files to keep suites discoverable. Platform shells (`app/android/`, `app/ios/`, `app/macos/`, `app/web/`, etc.) only hold generated runner code; add frontend assets under `app/assets/` and register them in `app/pubspec.yaml`. The Go backend now lives in `server/`, and new AI-related services should go under `ai-service/`.

## Build, Test, and Development Commands
- `cd app && flutter pub get` — install or refresh frontend dependencies after editing `app/pubspec.yaml`.
- `cd app && flutter run -d chrome` or `cd app && flutter run -d macos` — launch the Nexdo shell for rapid UI checks.
- `cd app && flutter test` — execute the widget and unit test suite locally.
- `cd app && flutter test --coverage` — optional but recommended to audit coverage before merging.
- `cd app && flutter analyze` — enforce the analyzer and `flutter_lints` rules; treat warnings as blockers.
- `cd server && go run ./cmd/api` — start the Go backend locally.
- `cd server && go test ./...` — run backend tests.

## Coding Style & Naming Conventions
Use Dart’s 2-space indentation for Flutter code and keep files in `snake_case.dart`. Classes, enums, and typedefs stay in `PascalCase`; variables and functions use `camelCase`. Prefer `const` widgets and trailing commas to unlock auto-formatting, then run `cd app && dart format lib test`. Follow dependency direction in Flutter code: presentation → domain → data, never the reverse. For Go code in `server/`, follow standard `gofmt` formatting and keep packages scoped by domain.

## Testing Guidelines
Rely on `flutter_test` for frontend widget tests and plain `package:test` APIs for pure Dart logic. Name every frontend spec with the `_test.dart` suffix and group cases with `group('feature/use_case', …)` so CI logs stay readable. Target 80% line coverage on new frontend modules; fail the PR if critical paths (auth gate, reminder scheduling) lack regression tests. Favor `WidgetTester` for stateful flows; add golden tests only when UI fidelity is critical. Backend changes in `server/` should include `go test ./...` coverage for affected packages.

## Commit & Pull Request Guidelines
Git history currently follows Conventional Commits (`feat: bootstrap nexdo flutter app and api design`), so continue using `feat|fix|chore|docs(scope): summary`. Keep commits scoped: UI tweaks, model changes, and build tooling should land separately. Every PR should include: problem statement, screenshots or screen recordings for UI-impacting work, test evidence (`flutter test` output or coverage diff), and links to tracking issues. Request review before merging and wait for green CI.

## Security & Configuration Tips
Frontend auth state relies on `SharedPreferences` (`app/lib/src/features/auth/data/auth_repository.dart`); never persist secrets or tokens in plain text and prefer platform keychains for sensitive values. Local notifications and timezone features require platform setup, so revisit `app/android/app/src/main/AndroidManifest.xml` and Apple entitlement files whenever you touch notification channels. Localization defaults to `Locale('zh','CN')` with `en_US` secondary; update both locale strings before shipping. Backend secrets should stay in environment variables under `server/`; do not commit JWT secrets or production database credentials.

## API Integration Notes
Flutter now relies on the Nexdo API running at `https://nexdo.kkw-cloud.cc/api/v1` by default via `NexdoApiClient`. Override the endpoint with `cd app && flutter run --dart-define=NEXDO_API_BASE_URL=https://your-host/api/v1` when pointing to other environments. Auth tokens and the latest `AuthUser` snapshot are stored under the `auth.session` key in `SharedPreferences`, and the `RemoteReminderWorkspaceRepository` keeps the reminder workspace cache in `ReminderLocalDataSource`. Always ensure the Go backend in `server/` (see `docs/api-technical-solution-go.md`) is up before launching the Flutter shell so `/auth/*` and `/sync/*` requests succeed.

Incremental sync first calls `GET /api/v1/sync/bootstrap` to cache the workspace plus `server_time`, then repeatedly hits `GET /api/v1/sync/changes?since=<server_time>`; the repository merges `deleted_*_ids` into local state and ReminderController polls every 30 seconds so reminders stay fresh without manual refresh.

## API Docs
https://nexdo.kkw-cloud.cc/api/v1/docs
