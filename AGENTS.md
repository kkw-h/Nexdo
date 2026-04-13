# Repository Guidelines

## Project Structure & Module Organization
Source entry lives in `lib/main.dart`, which bootstraps `lib/src/app.dart` and the feature-based tree under `lib/src/features/<feature>/{data,domain,presentation}` (e.g., `auth` and `reminders`)—follow this layering when adding flows. Tests mirror the source layout inside `test/…`; create `test/features/<feature>/*_test.dart` files to keep suites discoverable. Platform shells (`android/`, `ios/`, `macos/`, `web/`, etc.) only hold generated runner code; add assets under `assets/` and register them in `pubspec.yaml`.

## Build, Test, and Development Commands
- `flutter pub get` — install or refresh dependencies after editing `pubspec.yaml`.
- `flutter run -d chrome` or `flutter run -d macos` — launch the Nexdo shell for rapid UI checks.
- `flutter test` — execute the widget and unit test suite locally.
- `flutter test --coverage` — optional but recommended to audit coverage before merging.
- `flutter analyze` — enforce the analyzer and `flutter_lints` rules; treat warnings as blockers.

## Coding Style & Naming Conventions
Use Dart’s 2-space indentation and keep files in `snake_case.dart`. Classes, enums, and typedefs stay in `PascalCase`; variables and functions use `camelCase`. Prefer `const` widgets and trailing commas to unlock auto-formatting, then run `dart format lib test`. Follow dependency direction: presentation → domain → data, never the reverse.

## Testing Guidelines
Rely on `flutter_test` for widget tests and plain `package:test` APIs for pure Dart logic. Name every spec with the `_test.dart` suffix and group cases with `group('feature/use_case', …)` so CI logs stay readable. Target 80% line coverage on new modules; fail the PR if critical paths (auth gate, reminder scheduling) lack regression tests. Favor `WidgetTester` for stateful flows; add golden tests only when UI fidelity is critical.

## Commit & Pull Request Guidelines
Git history currently follows Conventional Commits (`feat: bootstrap nexdo flutter app and api design`), so continue using `feat|fix|chore|docs(scope): summary`. Keep commits scoped: UI tweaks, model changes, and build tooling should land separately. Every PR should include: problem statement, screenshots or screen recordings for UI-impacting work, test evidence (`flutter test` output or coverage diff), and links to tracking issues. Request review before merging and wait for green CI.

## Security & Configuration Tips
Auth state relies on `SharedPreferences` (`lib/src/features/auth/data/auth_repository.dart`); never persist secrets or tokens in plain text and prefer platform keychains for sensitive values. Local notifications and timezone features require platform setup, so revisit `android/app/src/main/AndroidManifest.xml` and Apple entitlement files whenever you touch notification channels. Localization defaults to `Locale('zh','CN')` with `en_US` secondary; update both locale strings before shipping.

## API Integration Notes
Flutter now relies on the Nexdo API running at `http://127.0.0.1:8080/api/v1` by default via `NexdoApiClient`. Override the endpoint with `flutter run --dart-define=NEXDO_API_BASE_URL=https://your-host/api/v1` when pointing to other environments. Auth tokens and the latest `AuthUser` snapshot are stored under the `auth.session` key in `SharedPreferences`, and the `RemoteReminderWorkspaceRepository` keeps the reminder workspace cache in `ReminderLocalDataSource`. Always ensure the Go backend (see `docs/api-technical-solution-go.md`) is up before launching the Flutter shell so `/auth/*` and `/sync/*` requests succeed.

Incremental sync first calls `GET /api/v1/sync/bootstrap` to cache the workspace plus `server_time`, then repeatedly hits `GET /api/v1/sync/changes?since=<server_time>`; the repository merges `deleted_*_ids` into local state and ReminderController polls every 30 seconds so reminders stay fresh without manual refresh.

## API Docs
http://127.0.0.1:8080/api/v1/docs
