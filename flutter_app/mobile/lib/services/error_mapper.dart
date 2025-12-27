class ErrorMapper {
  /// Map backend error codes/messages to user friendly messages.
  /// Extend this as server error contract evolves.
  static String friendlyMessage(dynamic error) {
    if (error == null) return 'An unknown error occurred.';

    // If server returns an object with code/message
    try {
      final code = error['code'];
      final message = error['message'] as String?;

      if (code != null) {
        switch (code.toString()) {
          case '401':
            return 'Authentication failed. Check your credentials.';
          case '403':
            return 'You do not have permission to perform this action.';
          case '400':
            return 'Incorrect username or password. Please check and try again.';
          case 'USER_NOT_FOUND':
            return 'User not found. Please check your username.';
          case 'INVALID_PASSWORD':
            return 'Incorrect password. Try again or reset your password.';
          default:
            if (message != null && message.isNotEmpty) return message;
            return 'An error occurred (code: $code). Please try again.';
        }
      }
    } catch (_) {
      // ignore and fallback
    }

    // If error is a string
    if (error is String) {
      final lower = error.toLowerCase();
      if (lower.contains('401') || lower.contains('unauthorized')) {
        return 'Authentication failed. Check your credentials.';
      }
      if (lower.contains('password')) {
        return 'There was a problem with the password. Please try again.';
      }
      return error;
    }

    return 'An unknown error occurred.';
  }
}
