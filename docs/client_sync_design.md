# Client-side Sync Design (Flutter)

This document describes a pragmatic client-side design for offline-first sync using a local SQLite DB (Drift / sqflite) and the server-side Postgres append-only `changes` table.

## Goals
- Allow full offline reads/writes on the mobile client.
- Keep a compact local change queue for pushes.
- Support idempotent create mapping (client temp ids -> server ids), checkpointing (last server_seq), and conflict handling.
- Make the client-side sync engine small and testable.

---

## Components
1. Local DB (Drift)
   - Tables:
     - `products` (app domain table)
     - `changes` (local change queue): columns: id (autoinc), client_seq (bigint autoinc), client_temp_id (text, nullable), entity_type (text), entity_id (text, nullable), operation (text), payload (json), created_at (datetime), pushed (boolean)
     - `sync_meta`: key/value table storing `last_server_seq`, `last_push_token`, etc.

2. Sync service
   - `push()`:
     - Gather unpushed `changes` (batched), send POST /api/sync/push with `client_id` and changes, receive `id_map` and `applied`/`conflicts`.
     - Apply server id mappings (replace local temp ids, update domain tables if necessary), mark local `changes` as pushed when acked.
     - Update `last_server_seq` checkpoint using returned `head_seq` or server_time as applicable.

   - `pull()`:
     - Call GET /api/sync/changes?since_seq=<last_server_seq>
     - Apply ordered changes to local DB in a transaction; update `last_server_seq` to `head_seq` from server.

3. Conflict handling
   - If POST /api/sync/push returns conflicts, present to user with `server_data` and `suggestion`. Support `force` flow for superadmin actions.
   - Maintain local `conflict` table (optional) for manual reconciliation UI.

---

## Example Drift schema (simplified)

```dart
// lib/sync/db.dart (example)
import 'package:drift/drift.dart';

class Products extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min:1, max:255)();
  RealColumn get price => real().withDefault(const Constant(0.0))();
  IntColumn get stockQuantity => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  IntColumn get storeId => integer().nullable()();
}

class Changes extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get clientSeq => integer().nullable()(); // optional
  TextColumn get clientTempId => text().nullable()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text().nullable()();
  TextColumn get operation => text()(); // create/update/delete
  TextColumn get payload => text().map(const JsonConverter())();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get pushed => boolean().withDefault(const Constant(false))();
}

class SyncMeta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text().nullable()();
  @override
  Set<Column> get primaryKey => {key};
}
```

> JsonConverter is a small Drift TypeConverter to store JSON in a TEXT column.

---

## Example push flow (pseudocode)

- Gather unpushed changes (limit 100).
- Convert each change into sync payload shape (resource_type, operation, temp_id, id, data, last_updated).
- POST to server: /api/sync/push with { client_id, changes }
- If success:
  - Update `sync_meta['last_server_seq']` and `changes.pushed = true` for applied entries.
  - For mappings in `id_map`, replace local temp ids in domain tables and persist mapping.
- If conflicts:
  - Save conflict entries to a local table and notify UI.

---

## Pull flow (pseudocode)

- Read last_server_seq from `sync_meta`.
- Call GET /api/sync/changes?since_seq=<last_server_seq>
- For each returned change, apply in server_seq order to local DB using transactions.
- Update `last_server_seq` = head_seq from response.

---

## Edge cases & tips
- Always use single-threaded write transactions when applying pull changes to avoid race conditions with local updates.
- For create operations: the server may return a mapping for the `client_temp_id` — update local rows to use server-assigned id or maintain a server_id column.
- For performance: compact local changes after successful push by deleting or marking as applied.
- Security: store minimal sensitive data locally; if storing tokens, prefer secure storage (flutter_secure_storage).

---

## Tests & QA
- Unit tests for: change queue enqueue/dequeue, id_map application, conflict handling behavior.
- Integration tests: seed local DB, simulate push (mock server) and pull responses, assert local DB state after operations.

---

If you'd like, I can add a small example implementation file `flutter_app/mobile/lib/sync/sync_service_example.dart` with concrete Dart code snippets for push/pull and a simple test harness.