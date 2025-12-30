# Changelog

## Unreleased

### 2025-12-28 — Phase 3 progress
- Added `ProductRepository` and `TransactionRepository` and integrated them into the app via providers. (files: `lib/data/repositories/product_repository.dart`, `lib/data/repositories/transaction_repository.dart`, `lib/data/providers.dart`)
- Implemented domain models mirroring backend authoritative schema (`lib/domain/models/*`).
- Added unit and provider tests for repository and provider behavior (`test/product_repository_test.dart`, `test/transaction_repository_test.dart`, `test/inventory_provider_repo_test.dart`, `test/pos_provider_repo_test.dart`).
- Added UI widget tests for Edit Product screen (`test/widget/edit_product_screen_test.dart`).
- Added an integration-style test to cover add → edit → delete (`test/widget/inventory_add_edit_delete_test.dart`) — test added but currently requires additional stabilization to run reliably in CI.

Notes: Integration test was instrumented to use `sqflite_common_ffi` (in-memory DB) and direct provider calls for determinism; some hangs/timeouts occurred and further fixes are planned.

### 2025-12-29 — Phase 2 complete
- Implemented `DatabaseHelper` schema and helper methods including transactional `insertProduct`, `updateStock`, `insertTransaction`, `deleteProduct`, and `sync_errors` logging (`lib/data/local/database_helper.dart`).
- Added transactional tests to verify atomicity and rollback behavior when `sync_queue` inserts fail: `test/data/local/database_helper_transaction_test.dart` (uses `sqflite_common_ffi` in-memory DBs). Tests pass locally and were verified along with `flutter analyze` and the full `flutter test` suite.

### 2025-12-28 — Phase 4 progress
- Implemented `AuthService` migration to `flutter_secure_storage` for token persistence and added atomicity for user persistence during login (`lib/services/auth_service.dart`).
- Added unit tests for `AuthService` verifying token save and rollback on failure (`test/auth_service_test.dart`) — tests pass locally.
- Notes: Login now writes token and persists user info to local `users` table; if persisting user information fails, token write is rolled back to avoid partial authenticated state.

### 2025-12-28 — Phase 5 complete
- Implemented `PostgresApiService` CRUD and initial seeding methods:
  - `fetchInitialData`, `fetchProducts`, `createProduct`, `updateProduct`, `deleteProduct` (file: `lib/data/remote/postgres_api_service.dart`).
- Added unit tests: `test/data/remote/postgres_api_service_test.dart` covering seeding, fetch, create/update/delete flows (tests pass locally).
- Testability: `PostgresApiService` accepts an injectable `http.Client`; tests use `test/test_utils/fake_http_client.dart` for deterministic responses.
- Docs: Updated `docs/offline_first_roadmap.md` to mark Phase 5 complete and documented implementation details and verification steps.

Notes: After Phase 5 changes, the full Flutter test suite runs green locally; this completes Phase 5 per the Implementation Policy (code, integration, tests, docs, verification).

### 2025-12-28 — Phase 6 complete
- Implemented `PostgresSyncService` enhancements and batch sync support:
  - Added `syncPendingChangesBatch` to aggregate pending changes and call `/api/sync/push`; batch handling applies `id_map`, `applied`, and `conflicts` atomically (file: `lib/data/sync/postgres_sync_service.dart`).
  - Restored per-item `syncPendingChanges` for backward compatibility and test stability.
- Connectivity & background integration:
  - Added `registerConnectivityListener(connectivity, {onConnected})` to `lib/sync/sync_background.dart` to trigger immediate syncs when connectivity is restored.
  - Workmanager registration & test coverage added (periodic registration, constraints, and failure handling).
- Tests and fixes:
  - Added batch tests (multiple `id_map`, mixed ops, server-provided `data` application) and per-item sync tests. Fixed test fakes (`TestSecureStorage` signatures and `FakeConnectivity`) to run under `flutter_test`.
  - Added Workmanager-related tests to assert constraints and exception handling.
- Result: Full Flutter test suite (unit, widget, background tests) passes locally after these changes.

Notes: Follow-up items included expanding batch-edge-case coverage and updating docs/CHANGELOG (this entry).

### 2025-12-29 — Phase 8 progress
- Added integration test that simulates a 409 conflict during background sync and verifies `sync_errors` insertion and retry behavior (`test/run_background_integration_test.dart`).
- Added CI workflow: `.github/workflows/flutter_ci.yml` runs `flutter analyze` and `flutter test` on push and pull requests.
- Notes: CI now runs unit and widget tests; suggestion: optionally add a CI service (dockerized backend) to run full integration tests against a live local backend.

### 2025-12-29 — Roadmap status updates
- Marked **Phase 1 — Project & Package Setup** as **COMPLETE** per the Implementation Policy: code added, providers wired, docs updated, and verification performed (`flutter analyze` + `flutter test` passed locally).
- Marked **Phase 4 — Authentication & Indefinite Session Persistence** as **COMPLETE** per the Implementation Policy: `AuthService` uses `flutter_secure_storage`, unit tests for token persistence and rollback exist and pass locally, and docs updated. 
