# UI Integration Roadmap — Apply Component Library Across App

This document describes the plan and per-screen checklist to integrate the new component library (tokens + components) into the running app, verify visual parity with captured goldens, and ensure accessibility and theme token compliance.

- Canonical theme tokens: `lib/theme/tokens.dart` (primaryBrand, primaryAction, secondaryAccent, warning, background, secondaryBackground, textBody)
- Verified golden baselines are referenced in `test/golden/*` and point to `goldens/*` images (e.g., `goldens/login_screen.png`, `goldens/home_screen.png`).

---

## High-level goals
- Replace legacy screen visuals with components (PrimaryButton, PrimaryTextField, MetricCard, ProductCard, LowStockPanel, etc.).
- Ensure all surfaces use token colors (AppColors.*) and ThemeData from `buildLightTheme()`.
- Add widget + accessibility tests and capture golden baselines after changes.
- Provide a dev toggle (debug FAB) to preview tokenized screens while migrating.

---

## Completed (so far)
- Login screen refactor completed and integrated with AuthProvider — golden: `goldens/login_screen.png`.
- Core components implemented and tested: `PrimaryButton`, `PrimaryTextField`, `MetricCard`, `CardItem`, `ProductCard`, `Toast`, `ConfirmDialog`.
- Home screen: migrated visuals to use `MetricCard` and token colors (changes committed), golden test already exists at `test/golden/home_screen_golden_test.dart`.
- Tokens updated to include `warning` color for low-stock indicator.

---

## Per-screen integration checklist (order of priority)

1) Login (DONE)
   - Components: `PrimaryTextField`, `PrimaryButton`
   - Tests: widget + accessibility + golden (`goldens/login_screen.png`) ✔

2) Home (IN PROGRESS — implemented)
   - Components: `MetricCard`, `StoreIndicator`, `AllStoresBanner`, quick action cards
   - Acceptance: All MetricCards use `AppColors`/theme colors and `Theme.of(context).textTheme` for typography; `home_screen` golden passes.
   - Tests: update/use `test/golden/home_screen_golden_test.dart` and `test/widget/home_summary_refactor_test.dart` ✔

3) POS
   - Components: `ProductCard`, `PrimaryButton (Pay)`, keyboard-friendly checkout inputs
   - Acceptance: Pay CTA uses `AppColors.primaryAction` (green), product cards use `AppColors.secondaryBackground` for surfaces, add golden `goldens/pos_screen.png`.

4) Inventory
   - Components: `ProductListItem`, `LowStockPanel` — ensure low-stock uses `AppColors.warning` and prominent contrast
   - Acceptance: Inventory golden `goldens/inventory_screen.png` updated; accessibility tap-size + contrast checks pass.

5) Analytics
   - Components: `MetricCard` variants — ensure positive/negative trend colors are clear and tokens used where appropriate
   - Acceptance: `goldens/analytics_screen.png` validated; accessibility checks pass for large numeric text color contrast.

6) Management screens (User / Store / Admin / Cashier)
   - Components: consistent form layout with `PrimaryTextField`, `ConfirmDialog`, management lists with `CardItem`/`ManagementListItem`
   - Acceptance: Golden baselines for `user_management`, `store_management` exist and should be updated if UI changes.

7) Receipts & Reports
   - Components: `ReceiptCard` uses `TimeService` for localized timestamps; ensure print/export styles match tokens
   - Acceptance: `goldens/receipts_screen.png` validated.

8) Settings & Misc Screens
   - Ensure consistent usage of tokens for app bar, icons and surface backgrounds (AppBar uses `AppColors.primaryBrand` and `foregroundColor` set to white).

---

## Golden & Test Strategy
- Run `flutter test test/golden --update-goldens` locally (set `UPDATE_GOLDENS=true`) after a visual change and check in new images.
- Each screen integration must add/validate:
  - Widget tests covering behavior
  - Accessibility test covering semantic labels and tap-targets
  - Golden test referencing `goldens/<screen>.png`

---

## Token usage guidance (short)
- primaryBrand (`AppColors.primaryBrand`) — primary app blue; app bars, primary visual accents, summary cards
- primaryAction (`AppColors.primaryAction`) — green for positive actions (Pay, success badges)
- secondaryAccent (`AppColors.secondaryAccent`) — accent for informational cards and secondary highlights
- warning (`AppColors.warning`) — use for low-stock and alerts (orange)
- surface / background — prefer `Theme.of(context).colorScheme.surface` and `background` tokens for surfaces and cards
- text colors: `Theme.of(context).colorScheme.onBackground` / `onSurface` as appropriate; inputs explicitly use black where needed

---

## Implementation steps for remaining work
1. Iterate screen-by-screen in priority order above. For each screen:
   - Replace legacy widgets with tokenized components
   - Run widget & accessibility tests; fix failures
   - Capture golden & review visually
   - Commit changes and update roadmap progress
2. Add a developer debug toggle (FAB or env flag) to switch between legacy/new UI for faster QA.
3. Schedule a final pass to ensure color contrast and keyboard navigation across all screens.

---

## Next immediate tasks (recommended)
- Finalize Home UI golden and run `test/golden/home_screen_golden_test.dart` locally and update baseline if deliberate changes are made.
- Continue with POS → Inventory → Management as prioritized tasks (0.5–1 day per screen for implementation + tests).

---

If you'd like, I can now:
- Run the Home golden test and update the baseline if you approve the visual change, and/or
- Open a PR-style patch summary with the files changed and tests updated.

Which should I do next? ✨
