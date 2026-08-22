import 'package:http/testing.dart';
import 'package:http/http.dart' as http;

typedef FakeHttpHandler = Future<http.Response> Function(http.Request);

/// Lightweight helper to register path-based handlers and produce a MockClient.
class FakeHttpClient {
  final List<MapEntry<Pattern, FakeHttpHandler>> _routes = [];

  void when(Pattern pathMatcher, FakeHttpHandler handler) =>
      _routes.add(MapEntry(pathMatcher, handler));

  http.Client build() {
    return MockClient((req) async {
      final path = req.url.path;
      for (final e in _routes) {
        final p = e.key;
        if (p is String) {
          if (path.endsWith(p)) return e.value(req);
        } else if (p is RegExp) {
          if (p.hasMatch(path)) return e.value(req);
        }
      }
      return http.Response('Not found', 404);
    });
  }
}
