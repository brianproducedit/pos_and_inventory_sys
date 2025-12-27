# Flutter Client Sync Demo — Plan (Drift + background queue) 📱⚡️

Goal: Build a lightweight Flutter demo that shows local-first CRUD using Drift (sqlite), a write queue that persists pending changes, and a background sync worker that calls the server `/api/sync/push` and `/api/sync/changes` endpoints with conflict handling.

## Objectives
- Demonstrate local CRUD for `Product` using Drift tables and streams
- Implement a durable write queue persisted in Drift for offline writes
- Implement a background sync worker (foreground isolate or background service depending on platform) with exponential backoff and resume
- Show a simple conflict resolution UI: when server returns conflicts, fetch server-data and show a small merge modal (allow admin to 'force' update if authenticated as superadmin)

## Architecture sketch
1. Drift DB
   - Table: products (id, name, description, price, stock_quantity, is_active, store_id, created_at, updated_at)
   - Table: sync_queue (id, client_temp_id, resource_type, operation, payload_json, last_attempt_at, retry_count)
2. Sync service (Dart)
   - pushChanges(): reads queued items, forms `/api/sync/push` payload, sends with Authorization header (JWT)
   - process response: apply server id mapping (temp_id→id), remove applied items, mark conflicts for UX
   - pullChanges(since): calls `/api/sync/changes` and applies upserts to local DB
   - background scheduling: use `workmanager` on Android and `background_fetch` or equivalent on iOS; use an isolate for desktop


### Implementation details (work I will do now)
- Add `workmanager` dependency and a background dispatcher (`lib/sync/sync_background.dart`) to run periodic `pushChanges`/`pullChanges`.
- Register periodic WorkManager task with conservative default (every 6 hours) and `NetworkType.connected` constraint.
- Add unit tests for dispatcher logic and small integration test to verify `pushChanges` is triggered from the worker.
- Ensure `pullChanges` uses persisted `last_sync_time` and updates shared preferences on success.
- Add manifest changes for Android and `RECEIVE_BOOT_COMPLETED` permission to ensure scheduled work persists across reboots.
- Acceptance criteria: Worker triggers `SyncService.pushChanges()` and `pullChanges()` reliably in unit tests; documentation for enabling background sync added to `docs/flutter_sync_plan.md` and `docs/roadmap.md`.

3. Auth
   - Store JWT in secure storage; demo will use superadmin creds seeded locally for convenience in the demo (documented)

## Conflict UX (minimal)
- On conflict from `/api/sync/push`:
  - Show a notification item in the app: "1 conflict on Product 'X'"
  - Open a small merge dialog showing server and local values (name, price, qty)
  - Actions:
    - Accept server version (discard local change)
    - Keep local version and re-push with `_force: true` (admin only; verify role)
    - Merge manually and re-push

## Test plan
- Local-only flow: create, update, delete products offline; ensure queue persists across app restarts and sync completes when online
- Conflict flow: update the same product on server and client with out-of-date timestamp and ensure the conflict is surfaced and handled
- Temp-id mapping: create product offline (temp id) and confirm it maps to server id after push

## Files to add (initial scaffolding)
- `flutter_app/mobile/lib/sync/` — sync service and queue
- `flutter_app/mobile/lib/db/` — Drift schema and DAOs
- `flutter_app/mobile/lib/ui/sync_demo/` — minimal UI and merge dialog

## Acceptance criteria
- Demo app can run locally and perform offline CRUD
- Queue persists across restarts and syncs successfully after network restoration
- Conflicts are detected and a minimal merge UI is shown

## Next steps (what I'll implement now)
1. Add this plan to `docs/flutter_sync_plan.md` (done)
2. Scaffold `flutter_app/mobile/lib/sync` with a basic sync service and example Drift table (I can open a PR with scaffold files and a simple demo screen next)
3. Add CI/mobile test notes and a checklist entry in the roadmap

---

If you'd like, I can proceed to scaffold the Flutter demo files now (create Drift table, queue table, and a minimal UI screen). Which platform to prioritize first: `mobile` (Android/iOS) or `desktop` (Windows macOS)? My recommendation: start with `mobile` (Android/iOS) since it maps to typical device offline use.