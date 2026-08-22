# API Documentation

The backend exposes a full RESTful API built with FastAPI.

## OpenAPI (Swagger) Docs

When the backend is running locally, the complete interactive API documentation is available at:
**[http://localhost:8000/docs](http://localhost:8000/docs)**

## Sync API Overview

The sync mechanism relies on specific endpoints designed to handle offline data:

- **Push Endpoint (`POST /sync/push`)**: Accepts a batch of operations (inserts, updates, deletes) from the mobile client. It uses the `clientId` (UUID) to ensure idempotency.
- **Pull Endpoint (`GET /sync/pull`)**: Returns all records created or modified since a given `last_sync_timestamp`.

### Authentication
All API routes (except login and healthcheck) require a Bearer token (JWT). The token is obtained via `POST /auth/token`.
