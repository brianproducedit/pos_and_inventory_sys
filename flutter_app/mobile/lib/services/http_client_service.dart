import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';

/// Custom exceptions for better error handling
class NetworkException implements Exception {
  final String message;
  final int? statusCode;
  final bool isTimeout;
  final bool isConnectionClosed;

  NetworkException(
    this.message, {
    this.statusCode,
    this.isTimeout = false,
    this.isConnectionClosed = false,
  });

  @override
  String toString() => 'NetworkException: $message';

  /// Check if this is a recoverable error that should be retried
  bool get isRetryable =>
      isTimeout ||
      isConnectionClosed ||
      statusCode == 502 ||
      statusCode == 503 ||
      statusCode == 504;
}

class OfflineException implements Exception {
  final String message;
  OfflineException([this.message = 'No network connection']);

  @override
  String toString() => 'OfflineException: $message';
}

/// A resilient HTTP client wrapper that handles connection issues gracefully
class ResilientHttpClient {
  final http.Client _client;
  final Connectivity _connectivity;
  final Duration defaultTimeout;
  final int maxRetries;
  final Duration retryDelay;

  ResilientHttpClient({
    http.Client? client,
    Connectivity? connectivity,
    this.defaultTimeout = const Duration(seconds: 15),
    this.maxRetries = 3,
    this.retryDelay = const Duration(milliseconds: 500),
  })  : _client = client ?? http.Client(),
        _connectivity = connectivity ?? Connectivity();

  /// Check if device has network connectivity
  Future<bool> isOnline() async {
    try {
      final result = await _connectivity.checkConnectivity();
      return result != ConnectivityResult.none;
    } catch (e) {
      debugPrint('ResilientHttpClient: connectivity check failed: $e');
      return true; // Assume online if check fails
    }
  }

  /// Perform a GET request with automatic retry and connection handling
  Future<http.Response> get(
    Uri url, {
    Map<String, String>? headers,
    Duration? timeout,
    int? retries,
    bool throwOnOffline = true,
  }) async {
    return _executeWithRetry(
      () => _client.get(url, headers: headers),
      url: url,
      method: 'GET',
      timeout: timeout ?? defaultTimeout,
      retries: retries ?? maxRetries,
      throwOnOffline: throwOnOffline,
    );
  }

  /// Perform a POST request with automatic retry and connection handling
  Future<http.Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
    int? retries,
    bool throwOnOffline = true,
  }) async {
    return _executeWithRetry(
      () => _client.post(url, headers: headers, body: body),
      url: url,
      method: 'POST',
      timeout: timeout ?? defaultTimeout,
      retries: retries ?? maxRetries,
      throwOnOffline: throwOnOffline,
    );
  }

  /// Perform a PUT request with automatic retry and connection handling
  Future<http.Response> put(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
    int? retries,
    bool throwOnOffline = true,
  }) async {
    return _executeWithRetry(
      () => _client.put(url, headers: headers, body: body),
      url: url,
      method: 'PUT',
      timeout: timeout ?? defaultTimeout,
      retries: retries ?? maxRetries,
      throwOnOffline: throwOnOffline,
    );
  }

  /// Perform a DELETE request with automatic retry and connection handling
  Future<http.Response> delete(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
    int? retries,
    bool throwOnOffline = true,
  }) async {
    return _executeWithRetry(
      () => _client.delete(url, headers: headers, body: body),
      url: url,
      method: 'DELETE',
      timeout: timeout ?? defaultTimeout,
      retries: retries ?? maxRetries,
      throwOnOffline: throwOnOffline,
    );
  }

  /// Execute an HTTP request with retry logic and proper error handling
  Future<http.Response> _executeWithRetry(
    Future<http.Response> Function() request, {
    required Uri url,
    required String method,
    required Duration timeout,
    required int retries,
    required bool throwOnOffline,
  }) async {
    // Check connectivity first
    if (!await isOnline()) {
      if (throwOnOffline) {
        throw OfflineException('No network connection');
      }
    }

    int attempt = 0;
    Exception? lastException;

    while (attempt < retries) {
      attempt++;
      try {
        debugPrint(
            'ResilientHttpClient: $method $url (attempt $attempt/$retries)');

        final response = await request().timeout(timeout);

        // Check for server errors that should be retried
        if (response.statusCode >= 500 && attempt < retries) {
          debugPrint(
              'ResilientHttpClient: Server error ${response.statusCode}, retrying...');
          await Future.delayed(retryDelay * attempt);
          continue;
        }

        return response;
      } on TimeoutException catch (e) {
        debugPrint('ResilientHttpClient: Timeout on attempt $attempt: $e');
        lastException = NetworkException(
          'Request timed out after ${timeout.inSeconds}s',
          isTimeout: true,
        );

        if (attempt < retries) {
          await Future.delayed(retryDelay * attempt);
          continue;
        }
      } on SocketException catch (e) {
        debugPrint('ResilientHttpClient: Socket error on attempt $attempt: $e');
        lastException = NetworkException(
          'Connection failed: ${e.message}',
          isConnectionClosed: true,
        );

        if (attempt < retries) {
          await Future.delayed(retryDelay * attempt);
          continue;
        }
      } on HttpException catch (e) {
        debugPrint('ResilientHttpClient: HTTP error on attempt $attempt: $e');

        // Handle "Connection closed before full header was received"
        final isConnectionClosed = e.message.contains('Connection closed') ||
            e.message.contains('closed before');

        lastException = NetworkException(
          e.message,
          isConnectionClosed: isConnectionClosed,
        );

        if (isConnectionClosed && attempt < retries) {
          await Future.delayed(retryDelay * attempt);
          continue;
        }
      } on http.ClientException catch (e) {
        debugPrint('ResilientHttpClient: Client error on attempt $attempt: $e');
        lastException = NetworkException(
          'Connection error: ${e.message}',
          isConnectionClosed: true,
        );

        if (attempt < retries) {
          await Future.delayed(retryDelay * attempt);
          continue;
        }
      } catch (e) {
        debugPrint(
            'ResilientHttpClient: Unexpected error on attempt $attempt: $e');
        lastException = NetworkException('Unexpected error: $e');

        // Only retry on likely transient errors
        if (e.toString().contains('Connection') && attempt < retries) {
          await Future.delayed(retryDelay * attempt);
          continue;
        }

        rethrow;
      }
    }

    throw lastException ??
        NetworkException('Request failed after $retries attempts');
  }

  /// Close the underlying HTTP client
  void close() {
    _client.close();
  }
}

/// Singleton instance for app-wide use
class HttpClientService {
  static final HttpClientService _instance = HttpClientService._internal();
  factory HttpClientService() => _instance;
  HttpClientService._internal();

  ResilientHttpClient? _client;

  ResilientHttpClient get client {
    _client ??= ResilientHttpClient();
    return _client!;
  }

  /// Reset the client (useful for testing or after significant network changes)
  void reset() {
    _client?.close();
    _client = null;
  }
}
