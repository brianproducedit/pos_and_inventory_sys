import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import '../test_utils/fake_http_client.dart';
import 'dart:convert';
import 'package:mobile/services/auth_service.dart';

void main() {
  test('login throws structured map when server returns JSON detail on 400',
      () async {
    final builder = FakeHttpClient();
    builder.when('/auth/token', (req) async {
      return http.Response(
          jsonEncode({'detail': 'incorrect username or password'}), 400,
          headers: {'content-type': 'application/json'});
    });
    final mockClient = builder.build();

    final service = AuthService(mockClient);

    try {
      await service.login('user', 'badpw');
      fail('Expected exception');
    } catch (e) {
      expect(e, isA<AuthException>());
      final ex = e as AuthException;
      expect(ex.message, contains('incorrect username or password'));
      expect(ex.code, 400);
    }
  });
}
