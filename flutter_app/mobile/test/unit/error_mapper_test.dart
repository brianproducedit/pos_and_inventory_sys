import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/services/error_mapper.dart';

void main() {
  test('Maps known numeric code 401', () {
    final msg = ErrorMapper.friendlyMessage({'code': 401});
    expect(msg, contains('Authentication failed'));
  });

  test('Maps named code USER_NOT_FOUND', () {
    final msg = ErrorMapper.friendlyMessage({'code': 'USER_NOT_FOUND'});
    expect(msg, contains('User not found'));
  });

  test('Falls back to message field', () {
    final msg =
        ErrorMapper.friendlyMessage({'code': 'X', 'message': 'Custom reason'});
    expect(msg, 'Custom reason');
  });

  test('Handles raw string', () {
    final msg = ErrorMapper.friendlyMessage('password invalid');
    expect(msg, contains('password'));
  });

  test('Handles null gracefully', () {
    final msg = ErrorMapper.friendlyMessage(null);
    expect(msg, contains('unknown'));
  });
}
