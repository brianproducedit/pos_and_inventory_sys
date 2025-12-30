# Store Switching Roadmap ✅

**Goal:** Fix and harden store switching so store context is honored across POS and related screens (products, inventory, sales, analytics), ensure role-based access is enforced, and add coverage + monitoring to prevent regressions.

---

## Quick checklist (tickable)

- [x] 1) Audit current behavior and reproduce issues 📋
  - Steps: collect failing flows, reproduce in local/dev, capture logs and screenshots.
  - Acceptance: clear repro steps and failing scenarios documented.

- [x] 2) Fix client-side store id handling (parsing + normalization) 🔧
  - Tasks: replace brittle `as int?` casts with robust parsing, normalize `0` → All Stores (null) consistently.
  - Acceptance: provider unit tests prove integer and string IDs both work and don't lead to global fallback.

- [x] 3) Ensure POS & related providers react to store changes reliably 🔁
  - Tasks: verify `setStoreProvider()` listeners, debounce logic, and explicit reloads on switch.
  - Acceptance: on store switch, only relevant screens reload and request correct store-scoped data.

- [x] 4) Add unit tests & widget tests for critical flows 🧪
  - Tests: store switch from StoreQuickAction, StoreIndicator updates, POS product filtering, inventory low-stock per store, sales history per store.
  - Acceptance: tests cover admin/superadmin/cashier edge cases and pass locally and in CI.

- [x] 5) Backend review: store context enforcement & tests 🛡️
  - Tasks: verify `X-Store-ID` handling, StoreContext logic, `switch` endpoint, and accessible stores queries for admin assignments.
  - Acceptance: server-side tests ensure requests without header fall back to persisted user store; unauthorized cases return 403.

- [x] 6) Add request-level diagnostics & telemetry 🔍
  - Tasks completed: added debug logging for outgoing `X-Store-ID` headers in `ProductService` and `SalesService`, added server-side logging for `/api/stores/switch` and stored structured `AnalyticsEvent` with `duration_ms` and `metadata_json` (contains `success`).
  - Acceptance: logs reveal store id sent and backend context used when repro'ing issues; analytics event contains `duration_ms` and `success` flag.

- [ ] 7) UI improvements & UX edge cases ✨
  - Tasks: prevent non-admin roles from seeing/choosing All Stores, disable All Stores option if not permitted; show clear messages when access denied.
  - Acceptance: StoreQuickAction and StoreIndicator show correct state and disabled options for restricted roles.

- [ ] 8) Integration / e2e tests (CI) 🔄
  - Tasks: add flows that switch stores and assert cross-screen state is consistent (POS, Inventory, Sales, Analytics).
  - Acceptance: e2e runs on CI environment and catches regressions.

- [ ] 9) Release candidate & staged rollout 🚀
  - Tasks: create RC build, test on staging, roll out to subset of users; monitor errors.
  - Acceptance: no critical errors and metrics show expected behavior.

- [ ] 10) Docs, changelog, and post-release monitoring 📚
  - Tasks: update docs (`docs/`), add changelog entry, set alerts for store-switch related errors.
  - Acceptance: updated docs and active monitoring in place.

---

## Timeline & owners (suggested)

- Week 1: Audit, quick fixes (parsing), and tests (Owner: Frontend engineer) — 2–3 days
- Week 1–2: Backend review & tests (Owner: Backend engineer) — 2–3 days
- Week 2: Add tests (unit/widget/e2e), UI tweaks (Owner: Frontend + QA) — 3–4 days
- Week 3: RC, staging validation, rollout (Owner: Release engineer / PM) — 2–3 days

> Adjust schedule according to team availability. Prioritize quick safety fixes (parsing and tests) first.

---

## Acceptance criteria (definition of done) ✅

- Store switching works consistently for all roles (superadmin/admin/cashier).
- POS shows only products for the selected store unless explicitly All Stores and permitted.
- Tests (unit, widget, e2e) cover the core flows and pass in CI.
- Logging is sufficient to trace `X-Store-ID` through client → server for debugging.
- Doc and changelog updated.

---

## Rollback plan

If post-release we observe regressions, roll back the release and revert the change set; use server-side logs and analytics events to replicate the issue and rework fixes on a feature branch.

---

## Notes & references

- Related code paths touched already: `StoreProvider`, `PosProvider`, `ProductService`, `InventoryProvider`, `StoreQuickAction`, `store_context` (backend).
- Tests to extend: `test/providers/pos_provider_test.dart`, widget tests for `PosScreen`, `StoreQuickAction`, and backend `test_store_switch_flow.py`.

---

_Last updated: 2025-12-30T00:00:00Z_
