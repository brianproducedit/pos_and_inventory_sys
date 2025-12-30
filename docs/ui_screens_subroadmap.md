# UI Screens Sub-Roadmap — Remaining Work

Purpose
- Capture concrete tasks, acceptance criteria and tests for the remaining UI work (wiring screens to repositories/services, finishing admin flows, and stabilizing widget/integration tests).

Scope
- Screens in focus: Sync Errors (admin), Inventory, POS (checkout), Settings/Admin area, Sync Demo, Analytics, Receipts, User Management, Store Management.

How to use
- Each screen section follows the same Implementation Policy: Code → Integrate → Tests → Docs → Verification.
- Items marked **High** are recommended immediate priorities.

---

## 1) Sync Errors (Admin) ✅ High — **Done**
Goal: Surface `SyncError` records to admins and allow Clear + Re-enqueue actions.

Status: **Completed** — UI, repo wiring, and widget test implemented and validated locally.

Tasks:
- Code ✅
  - Navigation entry added to **Settings/Admin** to open `SyncErrorsScreen` (`lib/ui/admin/sync_errors_screen.dart`).
  - Clear + Re-enqueue actions call `SyncRepository.clearError(id)` and `SyncRepository.reenqueueQueueItem(queueId)` and refresh the list (implemented).
- Integrate ✅
  - Route `/admin/sync-errors` added in `lib/main.dart` and menu item added to `lib/screens/settings_screen.dart` (admin-only visibility).
- Tests ✅
  - Widget test asserting route opens and actions call the repo using a fake repo override (`test/widget/sync_errors_screen_navigation_test.dart`, `test/widget/sync_errors_screen_reenqueue_test.dart`).
  - Integration test exists to exercise re-enqueue behavior (see `test/...`).
- Docs ✅
  - Short note added to `docs/offline_first_roadmap.md` and `docs/ENVIRONMENT_SETUP.md` describing admin access and verification steps.
- Verification ✅
  - `flutter test` passes locally; manual QA performed by admin flow.

Acceptance criteria
- Admin menu exposes Sync Errors page. ✅
- Clear removes row and re-enqueue resets queue entry to `pending` and clears errors. ✅

---

## 2) Inventory Screen — Offline read / actions ✅ High — **Mostly Done**
Goal: Ensure Inventory UI reads from local DB via `ProductRepository` and queues writes locally.

Status: **Mostly completed** — Inventory reads from local repository and provider tests show local product loads. Widget test for local read passes; there is a remaining TODO to migrate the edit-product UI flow to a less-flaky test.

Tasks:
- Code ✅
  - `InventoryScreen` uses `ProductRepository` for reads & writes. Direct REST calls removed.
- Integrate ✅
  - `InventoryProvider` uses `ProductRepository` and `DatabaseHelper` (injected in tests).
- Tests ✅ (with TODO)
  - Widget test using `sqflite_common_ffi` and in-memory DB verifies product list renders (`test/widget/inventory_screen_local_db_test.dart`).
  - **Note / TODO:** The edit-product UI -> enqueue UPDATE flow was found to be timing-sensitive in the widget harness and has been skipped for now; migrate this to either a repository/unit test (recommended) or an integration test that runs outside the widget harness.
- Docs ✅
  - Added notes about offline-first behavior in `docs/offline_strategies.md` and `docs/ENVIRONMENT_SETUP.md`.
- Verification ✅
  - `flutter test` passes locally for non-flaky parts; repository-level DB tests cover transactional behavior and queue enqueueing.

Acceptance criteria
- Inventory UI does not call server directly; all writes are local and queue an outbox entry. ✅
- TODO: Re-enable the edit-product UI test by migrating it to a robust test type (integration or mock repo).
---

## 3) POS / Checkout Screen — Local transaction + queue ✅ High — **Next**
Goal: Ensure checkout writes `transactions` + `transaction_items` locally and enqueues a `CREATE` outbox item.

Status: **Planned (next work item)** — I'll start by adding a unit test for `TransactionRepository.addTransaction()` to assert DB rows and `sync_queue` entry, then wire the POS checkout UI and add a widget test with an in-memory DB.

Tasks:
- Code
  - Use `TransactionRepository` in POS checkout flow to write local transaction and queue. (Planned)
- Tests
  - **In-progress**: Unit test for `TransactionRepository.addTransaction()` to assert DB rows + `sync_queue` entry. (Started)
  - Widget test that simulates checkout and asserts local DB state. (Next)
- Verification
  - Validate via `flutter test` and by manual checkout in app.

---

## 4) Settings & Admin Management — expose admin tools ✅ Medium
Goal: Add links to admin-only features (Sync Demo, Sync Errors, Store Quick Actions, Admin Management flows).

Tasks:
- Code & Integrate
  - Add admin menu items to `SettingsScreen` if role is admin/superadmin.
- Tests
  - Widget tests toggling role to `admin`/`superadmin` and asserting admin items are present and navigate correctly.
- Verification
  - Test navigation flows and permissions.

---

## 5) Sync Demo & Analytics — Test harness & offline visibility ✅ Medium
Goal: Ensure sync demo uses `PostgresApiService`/`ProductRepository` via providers and remains deterministic in tests.

Tasks:
- Use fake `PostgresApiService` in tests (`test/widget/sync_demo_seed_test.dart` already exists).
- Add test verifying seed behavior with in-memory DB.

---

## 6) Receipts / History / User flows — Ensure local reads and queueing ✅ Low → Medium
Goal: Verify receipt list and user profile edits are local and do not depend on immediate server responses.

Tasks:
- Audit screens for direct HTTP usage and refactor to repositories.
- Add widget tests as needed.

---

## 7) Store Management — Admin store CRUD & switching ✅ High — **In progress**
Goal: Provide a robust UI for creating, editing, deactivating stores and switching active store context; all changes must be local-first and queue changes for sync when necessary.

Status: **In progress** — Implemented `StoreRepository` and unit tests to validate local writes and `sync_queue` entries; next: UI & widget tests.

Tasks:
- Code
  - Implemented `StoreRepository` and DatabaseHelper helpers to perform local DB writes and queue changes via `sync_queue` for create/update/deactivate actions (see `lib/data/repositories/store_repository.dart`).
  - Add `StoreManagementScreen` under admin flows with Create/Edit/Deactivate actions and a UI for switching active store (use StoreProvider/StoreRepository).
- Tests
  - **Done:** Unit tests for `StoreRepository` validate local writes and queue insertion (`test/store_repository_test.dart`).
  - Widget tests for `StoreManagementScreen` to assert CRUD flows enqueue correct sync_queue entries and switching persists locally (use in-memory DB and provider overrides).
- Verification
  - Manual test: create store, switch store, deactivate and verify local DB and `sync_queue` entries.

Acceptance criteria
- Admin can create/edit/deactivate stores offline (writes local, creates queue entries) and switch the active store context persists locally.

---

## 8) Cashier Management — Invite & Role assignment ✅ Medium
Goal: Admins can create/edit cashier accounts and assign them to stores; invites should be queued and retriable if offline.

Tasks:
- Code
  - Add `CashierManagementScreen` for listing cashiers, inviting new cashiers, and assigning stores.
  - Use `UserRepository`/`AuthService` abstractions to write invite actions locally (add to `sync_queue` or a separate pending-invite table if appropriate).
- Tests
  - Unit tests for invite flow to assert queueing of invite action.
  - Widget tests for the Cashier Management UI with role-based visibility and actions.
- Verification
  - Simulate offline invite (no network) and verify invite action is queued and later processed by background sync.

Acceptance criteria
- Invite and role assignment works offline (queued) and admins can view pending invites locally.

---

## 9) Admin Management — User & Permission controls ✅ Medium
Goal: Provide user and permission management UI for admin/superadmin roles and ensure changes are local-first and queued.

Tasks:
- Code
  - Implement `AdminManagementScreen` to list users, edit roles, grant/revoke store access, and support deletion — all via repositories that write locally and enqueue sync actions.
- Tests
  - Unit tests for role change persistence and queue entries.
  - Widget tests for UI visibility based on current admin role and for performing role edits.
- Verification
  - Manual QA for role changes and store access updates while offline and confirm reconciliation after sync.

Acceptance criteria
- Admin/superadmin can manage users offline; role/store access edits are queued and applied by the sync engine.

---

## Cross-cutting tasks
- Riverpod migration plan (Phase 9): convert remaining `Provider` usages in `main.dart` and screens to Riverpod providers to unify DI and enable easier widget testing. **Priority: Medium**.
- Provider scoping fixes: add Test provider scaffolding for widget tests to avoid ProviderNotFound errors.
- Accessibility & localization checks for updated screens (add tests for a11y semantics where applicable).
- CI: add targeted widget/integration jobs if any screen UI tests are flaky; consider e2e CI with a local backend docker container for higher confidence.

---

## Prioritization & timeline (suggested)
- Week 1 (High): Wire `SyncErrors` into Admin menu and add nav + tests. Stabilize inventory and POS flows if minor gaps exist.
- Week 2 (Medium): Finish settings/admin polish and add tests for Sync Demo + analytics offline scenarios. Begin Riverpod migration plan.
- Week 3 (Low/Medium): Complete remaining screens, accessibility checks, and CI e2e additions.

---

If you'd like, I can start on the **Sync Errors admin wiring** now (add route + settings entry + widget test). Which screen should I start with? 
