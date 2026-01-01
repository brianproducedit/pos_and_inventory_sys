import 'package:mobile/services/auth_service.dart';
import 'package:flutter/foundation.dart';

class ErrorMapper {
  /// Map backend error codes/messages to user friendly messages.
  /// Extend this as server error contract evolves.
  static String friendlyMessage(dynamic error) {
    if (error == null) return 'An unknown error occurred.';

    // If server returns an object with code/message (Map or AuthException)
    try {
      dynamic code;
      String? message;
      if (error is Map) {
        code = error['code'];
        message = error['message'] as String?;
      } else if (error is AuthException) {
        code = error.code;
        message = error.message;
      }

      if (code != null) {
        final codeStr = code.toString();
        switch (codeStr) {
          case '400':
            return 'Incorrect username or password. Please check and try again.';
          case '401':
            return 'Authentication failed. Check your credentials.';
          case '403':
            return 'You do not have permission to perform this action.';
          default:
            // For other codes, check if we have a meaningful message
            if (message != null && message.isNotEmpty) {
              // If the message is already user-friendly, use it
              if (!message.contains('HTTP') && !message.contains('status')) {
                return message;
              }
            }
            return 'An error occurred (code: $codeStr). Please try again.';
        }
      }

      // No code available, check message
      if (message != null && message.isNotEmpty) {
        // Check for common error patterns
        final lower = message.toLowerCase();
        if (lower.contains('incorrect') ||
            lower.contains('invalid') ||
            lower.contains('wrong')) {
          return 'Incorrect username or password. Please check and try again.';
        }
        if (lower.contains('unauthorized') || lower.contains('401')) {
          return 'Authentication failed. Check your credentials.';
        }
        if (lower.contains('forbidden') || lower.contains('403')) {
          return 'You do not have permission to perform this action.';
        }
        // If message looks user-friendly, use it
        if (message.length < 100 &&
            !message.contains('HTTP') &&
            !message.contains('{') &&
            !message.contains('}')) {
          return message;
        }
      }
    } catch (e) {
      debugPrint('Error in friendlyMessage parsing: $e');
      // ignore and fallback
    }

    // If error is a string
    if (error is String) {
      final lower = error.toLowerCase();
      if (lower.contains('401') || lower.contains('unauthorized')) {
        return 'Authentication failed. Check your credentials.';
      }
      if (lower.contains('password') ||
          lower.contains('incorrect') ||
          lower.contains('invalid')) {
        return 'There was a problem with your login credentials. Please try again.';
      }
      if (lower.contains('network') || lower.contains('connection')) {
        return 'Network error. Please check your connection and try again.';
      }
      // Return the string if it's short and looks like a user message
      if (error.length < 100) {
        return error;
      }
    }

    return 'An unknown error occurred. Please try again.';
  }
}
