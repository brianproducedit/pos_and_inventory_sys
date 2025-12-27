import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:convert';
import 'package:mobile/services/auth_service.dart';

void main() {
  test('login throws structured map when server returns JSON detail on 400',
      () async {
    final mockClient = MockClient((req) async {
      return http.Response(
          jsonEncode({'detail': 'incorrect username or password'}), 400,
          headers: {'content-type': 'application/json'});
    });

    final service = AuthService(mockClient);

    try {
      await service.login('user', 'badpw');
      fail('Expected exception');
    } catch (e) {
      expect(e, isA<Map>());
      final Map m = e as Map;
      expect(m['message'], contains('incorrect username or password'));
      expect(m['code'], 400);
    }
  });
}
