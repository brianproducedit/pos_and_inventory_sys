# Sync API Spec (Draft)

**Purpose:** define the minimal push/pull API for offline-first clients.

## Concepts
- server_seq: monotonically increasing sequence for change ordering (from `changes` table).
- client_seq: per-client monotonic counter for local ops (client-generated; optional for idempotency).
- temp_id: client-generated UUID used for newly created local records before server-assigned IDs.

---

## Endpoints

### GET /api/sync/changes
Fetch server-side changes since the provided `since_seq` (exclusive).

Query params:
- since_seq (int, required) — last server_seq seen by client (0 to start from beginning)
- limit (int, optional, default 500) — max number of change rows to return
- types (csv string, optional) — filter by entity_type (e.g., "products,sales")

Response (200):
{
  "changes": [
    {
      "server_seq": 1234,
      "entity_type": "product",
      "entity_id": "42",
      "operation": "update",
      "payload": { ... },
      "origin_client_id": "client-abc",
      "created_at": "2025-12-30T00:00:00Z"
    },
    ...
  ],
  "head_seq": 1240
}

Behavior:
- Returns changes ordered by `server_seq` ascending.
- `head_seq` is the current highest server_seq at the time of the response.

---

### POST /api/sync/push
Apply a batch of client changes. The server must apply changes transactionally where possible and return mapping for any new server-generated IDs and conflict records.

Request body:
{
  "client_id": "client-abc",
  "client_seq": 456, // optional checkpoint for this batch
  "changes": [
    {
      "temp_id": "tmp-1", // optional, used for newly created records
      "entity_type": "product",
      "entity_id": "42", // optional for creates; server may return final id
      "operation": "create|update|delete",
      "payload": { ... },
      "last_known_server_seq": 100 // optional, used for optimistic conflict checks
    },
    ...
  ]
}

Response (200):
{
  "applied": [
    {"temp_id": "tmp-1", "server_id": 123},
    {"entity_type": "product", "entity_id": 42, "server_seq": 1235}
  ],
  "conflicts": [
    {"entity_type": "product", "id": 42, "message": "Conflict: server has newer record", "server_data": { ... }}
  ],
  "server_time": "2025-12-30T00:00:00Z"
}

Behavior & guarantees:
- The server should detect and report conflicts when `last_known_server_seq` < current `server_seq` for that entity.
- Server should be idempotent where possible: repeated pushes of the same change (identified by client_id + client_seq or temp_id) should not create duplicates.
- Server must write an entry to `changes` for each applied operation, each with an increasing `server_seq`.

---

## Error handling
- 400 Bad Request: invalid payload
- 401 Unauthorized: invalid token
- 409 Conflict: non-recoverable conflict requiring client resolution (prefer returning conflicts in 200 with `conflicts` array)
- 500 Server Error: transient errors — client should retry with backoff

---

## Idempotency & dedup
- Clients should include `client_id` and a monotonically increasing `client_seq` per batch.
- Server keeps a small cache or table of recent `(client_id, client_seq)` to deduplicate repeated batches.

---

## Notes & next steps
- Formalize conflict rules per entity (e.g., for `Inventory` use server-side aggregation and optimistic locking).
- Add tests for ordering, idempotency, and conflict cases.
- Decide on batch size limits and retention/compaction policy for `changes`.
