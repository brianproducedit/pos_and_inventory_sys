FakeHttpClient helper

What
- `FakeHttpClient` is a tiny path-matching helper that builds an `http.MockClient` with route handlers.
- Use it to standardize how tests stub HTTP endpoints. It matches suffixes (endsWith) and RegExp patterns.

Example

```
final builder = FakeHttpClient();
builder.when('/api/sync/push', (req) async {
  return http.Response(jsonEncode({'applied': [], 'conflicts': []}), 200,
      headers: {'content-type': 'application/json'});
});
final client = builder.build();
// pass `client` to service constructors for deterministic tests
```

Why
- Keeps tests consistent and readable.
- Centralizes mappings so future helpers (assertion helpers, common JSON shapes) can be added in one place.

Notes
- For complex streaming or multipart responses, implement a custom `http.BaseClient` in the test instead.
