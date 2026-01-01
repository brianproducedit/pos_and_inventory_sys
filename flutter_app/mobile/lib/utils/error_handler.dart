import 'package:flutter/material.dart';

/// Centralized error handling and user feedback system
class ErrorHandler {
  /// Show a user-friendly error message
  static void showError(BuildContext context, String message, {
    String? title,
    Duration duration = const Duration(seconds: 4),
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null)
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  Text(message),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: Colors.red.shade700,
        duration: duration,
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'DISMISS',
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  /// Show a success message
  static void showSuccess(BuildContext context, String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green.shade700,
        duration: duration,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Show a warning message
  static void showWarning(BuildContext context, String message, {
    String? title,
    Duration duration = const Duration(seconds: 4),
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.warning_amber_outlined, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null)
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  Text(message),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: Colors.orange.shade700,
        duration: duration,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Show info message
  static void showInfo(BuildContext context, String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.blue.shade700,
        duration: duration,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Show offline mode indicator
  static void showOfflineIndicator(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.cloud_off, color: Colors.white),
            SizedBox(width: 12),
            Expanded(
              child: Text('You are offline. Changes will sync when online.'),
            ),
          ],
        ),
        backgroundColor: Colors.grey.shade800,
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Show sync progress indicator
  static void showSyncProgress(BuildContext context, {
    required int synced,
    required int total,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Syncing... $synced/$total items'),
            ),
          ],
        ),
        backgroundColor: Colors.blue.shade700,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Show error dialog with retry option
  static Future<bool?> showErrorDialog(
    BuildContext context, {
    required String title,
    required String message,
    bool showRetry = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red.shade700),
            const SizedBox(width: 8),
            Text(title),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('CANCEL'),
          ),
          if (showRetry)
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('RETRY'),
            ),
        ],
      ),
    );
  }

  /// Convert exceptions to user-friendly messages
  static String getFriendlyMessage(dynamic error) {
    if (error == null) return 'An unknown error occurred';

    final errorString = error.toString().toLowerCase();

    // Network errors
    if (errorString.contains('socket') ||
        errorString.contains('network') ||
        errorString.contains('connection')) {
      return 'Cannot connect to server. Please check your internet connection.';
    }

    // Timeout errors
    if (errorString.contains('timeout')) {
      return 'Request timed out. Please try again.';
    }

    // Authentication errors
    if (errorString.contains('unauthorized') ||
        errorString.contains('authentication')) {
      return 'Invalid username or password.';
    }

    // Permission errors
    if (errorString.contains('permission') ||
        errorString.contains('forbidden')) {
      return 'You do not have permission to perform this action.';
    }

    // Validation errors
    if (errorString.contains('validation') ||
        errorString.contains('invalid')) {
      return 'Invalid input. Please check your data and try again.';
    }

    // Duplicate errors
    if (errorString.contains('duplicate') ||
        errorString.contains('unique constraint')) {
      return 'This item already exists. Please use a different name or ID.';
    }

    // Stock errors
    if (errorString.contains('insufficient stock') ||
        errorString.contains('out of stock')) {
      return 'Insufficient stock available for this product.';
    }

    // Server errors
    if (errorString.contains('500') ||
        errorString.contains('server error')) {
      return 'Server error occurred. Please try again later.';
    }

    // Default message
    return error.toString().length > 200
        ? 'An error occurred. Please try again.'
        : error.toString();
  }

  /// Handle repository operation errors
  static Future<T?> handleOperation<T>(
    BuildContext context, {
    required Future<T> Function() operation,
    String? successMessage,
    String? errorTitle,
    bool showLoading = false,
  }) async {
    try {
      if (showLoading) {
        showInfo(context, 'Processing...');
      }

      final result = await operation();

      if (successMessage != null) {
        showSuccess(context, successMessage);
      }

      return result;
    } catch (e) {
      showError(
        context,
        getFriendlyMessage(e),
        title: errorTitle ?? 'Error',
      );
      return null;
    }
  }

  /// Show confirmation dialog
  static Future<bool> showConfirmDialog(
    BuildContext context, {
    required String title,
    required String message,
    String confirmText = 'CONFIRM',
    String cancelText = 'CANCEL',
    bool isDestructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(cancelText),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: isDestructive
                ? ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                  )
                : null,
            child: Text(confirmText),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  /// Show loading overlay
  static void showLoadingOverlay(BuildContext context, {
    String message = 'Loading...',
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => WillPopScope(
        onWillPop: () async => false,
        child: Center(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    message,
                    style: const TextStyle(fontSize: 16),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Hide loading overlay
  static void hideLoadingOverlay(BuildContext context) {
    Navigator.of(context, rootNavigator: true).pop();
  }
}

/// Extension to make error handling easier in widgets
extension ErrorHandlingExtension on BuildContext {
  void showError(String message, {String? title}) {
    ErrorHandler.showError(this, message, title: title);
  }

  void showSuccess(String message) {
    ErrorHandler.showSuccess(this, message);
  }

  void showWarning(String message, {String? title}) {
    ErrorHandler.showWarning(this, message, title: title);
  }

  void showInfo(String message) {
    ErrorHandler.showInfo(this, message);
  }

  Future<bool> showConfirm({
    required String title,
    required String message,
    bool isDestructive = false,
  }) {
    return ErrorHandler.showConfirmDialog(
      this,
      title: title,
      message: message,
      isDestructive: isDestructive,
    );
  }
}
