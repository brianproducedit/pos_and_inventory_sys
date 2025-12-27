# Offline-first Strategy & Sync Options ⚡️

This document summarizes practical offline-first approaches and references to help design reliable local-first behavior for the POS & Inventory app (Flutter + FastAPI).

## High-level recommendations

- Use a local relational or document DB on-device for core read/write operations (SQLite, Drift, Hive, etc.). Make writes durable locally and defer remote sync.
- Keep authentication and critical admin seed data idempotent and reproducible on every device start (we seed `superadmin` at startup and mark `must_change_password=True`).
- Implement a local write queue and background sync worker that sends batched changes to the server when network becomes available.
- Use incremental replication (only send diffs / new changes) and a versioned API to reduce bandwidth and make sync resumable.
- Define a conflict resolution strategy up-front: simple approaches (last-write-wins, merge with timestamps) are easy, or use CRDTs for complex multi-user collaboration where convergence is required.
- Encrypt sensitive data at rest when device-level threats are a concern, and store long-lived secrets in platform secure storage.

## Client-side options (Flutter)

- Drift (https://drift.simonbinder.eu) — a full-featured SQLite-based ORM-like library with streaming queries and migrations; excellent for complex relational schemas.
- Hive — lightweight key/value store for simple structured data with fast performance.
- Local queuing + background isolate/service for retries and batched uploads.

## Server-side / replication options

- CouchDB + PouchDB model — built-in replication protocol for easy sync between server and clients (PouchDB on client, CouchDB on server). Good for document-style data and automatic replication.
- Custom sync API — use incremental change feeds (change tokens, per-entity last-updated timestamps or CDC) so clients can fetch only new data.
- Consider master-master or master-slave replication depending on the conflict model you choose.

## Conflict resolution

- Last-write-wins (timestamp-based) — simplest but can lose updates.
- Merge by business rules (e.g., aggregate counters by summing, pick highest-priority source).
- CRDTs (https://crdt.tech/) — best for collaborative or multi-conflict scenarios where automatic, deterministic convergence is required.

## Practical features to implement for this app

- Local offline mode with full CRUD for products, stores, sales, and users.
- Background sync with retry/backoff, resumable uploads, and diagnostic logs for failures.
- Administrative seeding and a CLI `scripts/prune_sqlite.py` to sanitize device DBs and keep only the seed `superadmin`.
- Data versioning and lightweight schema migrations to avoid incompatibility across app versions.
- Security: keep password seeds out of code; store secrets in `.env` (or platform secret stores in production) and enforce `must_change_password` for seeded admin.


## Server sync API (initial implementation)

- Endpoints added:
  - `GET /api/sync/changes?since=<ISO timestamp>&types=products` — returns product upserts and deletions (based on audit logs) since the given time.
  - `POST /api/sync/push` — accepts a batch of changes (create/update/delete) and returns applied changes, conflicts, and temporary-id to server-id mappings.

- Current scope: product resources, stores, and users (server-side support for these resources has been implemented; client-side support is still needed).

- Update: server-side handling includes create/update/delete and basic conflict reporting; next step is client sync worker and richer conflict resolution strategies.

- Example push payload:

```json
{
  "client_id": "device-123",
  "changes": [
    {
      "resource_type": "product",
      "operation": "create",
      "temp_id": "tmp-1",
      "data": {"name": "New Prod", "price": 5.0, "stock_quantity": 10, "store_id": 1}
    }
  ]
}
```

- Conflicts: the server returns a `conflicts` list when the server-side record is newer than client's `last_updated` timestamp; client should fetch server state and present merge UI or retry.

- Next steps: extend to more resource types, implement strong conflict resolution options (strategic merge, CRDTs where appropriate), and add a Flutter example client sync worker.

- Update: server-side conflict handling now returns a `suggestion` field for conflicts and supports a superadmin-only `_force: true` overwrite flag in change `data` to accept client updates despite timestamp mismatches.

## References

- Service Workers & Offline (MDN): https://developer.mozilla.org/en-US/docs/Web/Progressive_web_apps/Offline_service_workers
- PouchDB (client-side sync example): https://pouchdb.com/
- CouchDB Replication: https://docs.couchdb.org/en/stable/replication/index.html
- CRDTs overview: https://crdt.tech/
- Drift (Flutter SQL library): https://drift.simonbinder.eu/

---

If you'd like I can: 
- Add a minimal client-side sketch (Flutter) architecture showing where to store the write queue and how to trigger syncs; or
- Start implementing the server-side incremental sync endpoints and tests for basic replication.
