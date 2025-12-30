# Store & Role Scope Roadmap ✅

This checklist documents required behavior, tests, and integration scenarios to ensure the app properly scopes data and actions by **store** and **user role**.

## Goals 🎯
- Ensure **superadmin** can view and manage all stores (global view / All Stores).
- Ensure **admin** can view/manage only assigned stores.
- Ensure **non-admin** users (staff) can only access their assigned store's data.
- Ensure APIs are called with `X-Store-ID` header where appropriate and fall back sensibly to persisted `current_store_id`.
- Add unit, integration, and e2e tests covering role × resource combinations.

---

## Quick checklist (developer-friendly) 🔧
- [x] Server enforcement acknowledged: backend remains the final authority on access control.
- [x] Client-side guard: `StoreProvider.switchStore` denies All Stores (id==0) unless role in `['admin','superadmin']`.
- [x] `SalesService.createSale` and `getReceipt` accept an optional `storeId` and add `X-Store-ID` header.
- [x] `PosProvider` passes the current store id to `SalesService.createSale`.
- [x] Receipt screen uses store context when fetching receipts (was updated and tested).
- [x] Add explicit unit tests for `SalesService` behavior verifying `X-Store-ID` header inclusion. (see `test/unit/sales_service_test.dart`)
- [x] Add integration tests (API + client) for role-based denial/allow flows. (see `test/providers/store_provider_test.dart` and `test/integration/admin_switch_denial_test.dart`)
- [x] Add e2e tests covering: store creation by superadmin, admin assignment, admin switching, and cross-store access denial. (see `test/e2e/all_stores_e2e_test.dart`)
- [x] Add UI tests verifying presence/absence of `All Stores` UI options based on role. (see `test/widget/store_quick_action_visibility_test.dart`)

---

## Completed tests ✅

- `test/unit/sales_service_test.dart` — verifies `X-Store-ID` header for `createSale` and `getReceipt`.
- `test/widget/receipt_screen_test.dart` — ensures `ReceiptScreen` passes storeId to `SalesService`.
- `test/providers/store_provider_test.dart` — store switching permission and backend-deny behavior.
- `test/integration/admin_switch_denial_test.dart` — integration-style provider test for admin denial.
- `test/integration/superadmin_create_assign_test.dart` — superadmin create & assign flow.
- `test/e2e/all_stores_e2e_test.dart` — E2E-style test for All Stores aggregation (refined to be deterministic; in-progress validation across full suite).

---

## Test matrix (suggested) ✅/⚠️
| Role \ Resource | Products | Sales/Receipts | Analytics | Store Management |
|---|---:|---:|---:|---:|
| Superadmin | View/Edit all stores ✅ | Create/View receipts globally ✅ | Global reports ✅ | Create/assign stores ✅ |
| Admin (assigned stores) | View/Edit assigned ✅ | Create/View receipts for assigned ✅ | Reports for assigned stores ✅ | Manage assigned stores ✅ |
| Cashier | View assigned store only ✅ | Create/View receipts only for assigned ✅ | View limited analytics ⚠️ | No store management ⚠️ |

Notes:
- ⚠️ indicates higher-priority tests to add (integration/e2e), since unit tests may not catch backend enforcement.

---

## Integration / e2e scenarios (examples) 🧪
- Superadmin creates a new store, assigns admin A, then views reports across stores.
- Admin A attempts to switch to Admin B's store -> backend should deny, client should show an error.
- Admin A tries to switch to All Stores -> backend should deny unless role is admin/superadmin; client should hide/disable option for non-admin.
- Non-admin tries to fetch receipts for store they do not belong to -> backend 403, client handles gracefully.

---

## Implementation notes & tips 💡
- Prefer sending `X-Store-ID` header in services (products, sales, analytics). Services should fall back to persisted `current_store_id` when `storeId` is not supplied.
- Keep client-side role checks defensive and informative (UX), but do not rely on them for security.
- Use the `sqflite_common_ffi` in-memory db for deterministic tests for database-related changes.
- When adding tests that involve `StoreProvider`, prefer to mock `StoreService` responses or inject a test `StoreProvider` instance with controlled state.

---

## Next steps (priority)
1. Add unit tests for `SalesService` to assert `X-Store-ID` header usage. (High) — **Completed** (`test/unit/sales_service_test.dart`)
2. Add integration tests for cross-role access denial (e.g., admin accessing other admin's store). (High) — **Completed** (`test/integration/admin_switch_denial_test.dart`, `test/providers/store_provider_test.dart`)
3. Add e2e test flows for store creation, assignment, and role verification. (Medium) — **In progress** (`test/e2e/all_stores_e2e_test.dart`) — refining to be deterministic across CI.
4. Add UI tests verifying `All Stores` availability per role. (Medium) — **Done** (`test/widget/store_quick_action_visibility_test.dart`); consider adding more per-screen coverage.
5. Add documentation section for developers explaining how `current_store_id` is persisted and normalized. (Low) — **Partial**: roadmap and inline comments cover core behavior; suggest a short dev note in `docs/`.

---

**Next action:** finish the All Stores e2e refinement, run the full test suite, fix regressions, and then add a short developer doc about `current_store_id` persistence.

---

If you'd like, I can start implementing the high-priority unit tests for `SalesService` and add the integration scenarios next. 👍