import 'package:flutter/material.dart';

import 'data_protection_service.dart';

/// Observer that monitors app lifecycle events and triggers appropriate
/// data protection actions.
///
/// Key lifecycle events handled:
/// - paused: App going to background - create backup
/// - detached: App being terminated - export for uninstall protection
/// - resumed: App coming to foreground - verify integrity
class AppLifecycleObserver with WidgetsBindingObserver {
  final DataProtectionService _dataProtection;

  bool _isFirstResume = true;
  DateTime? _lastPauseTime;

  /// How long the app must be paused before we consider it a "long pause"
  /// that warrants extra protection measures
  static const Duration _longPauseThreshold = Duration(minutes: 5);

  AppLifecycleObserver(this._dataProtection);

  /// Start observing lifecycle events
  void startObserving() {
    WidgetsBinding.instance.addObserver(this);
    debugPrint('🔄 AppLifecycleObserver: Started observing');
  }

  /// Stop observing lifecycle events
  void stopObserving() {
    WidgetsBinding.instance.removeObserver(this);
    debugPrint('🔄 AppLifecycleObserver: Stopped observing');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint('📱 App lifecycle state changed: $state');

    switch (state) {
      case AppLifecycleState.paused:
        _handlePaused();
        break;
      case AppLifecycleState.resumed:
        _handleResumed();
        break;
      case AppLifecycleState.detached:
        _handleDetached();
        break;
      case AppLifecycleState.inactive:
        // Brief inactive state, no action needed
        break;
      case AppLifecycleState.hidden:
        // Hidden state (multi-window), treat similar to paused
        _handlePaused();
        break;
    }
  }

  /// Handle app going to background
  Future<void> _handlePaused() async {
    _lastPauseTime = DateTime.now();

    try {
      // Create a quick backup when app goes to background
      debugPrint('💾 Creating background backup...');
      await _dataProtection.createBackup(reason: 'app_paused');

      // Checkpoint WAL to ensure data is persisted
      await _dataProtection.checkpointWAL();
    } catch (e) {
      debugPrint('⚠️ Background backup failed: $e');
    }
  }

  /// Handle app coming to foreground
  Future<void> _handleResumed() async {
    try {
      // On first resume, check for data to import (reinstall scenario)
      if (_isFirstResume) {
        _isFirstResume = false;

        debugPrint('🔍 First resume - checking for reinstall data...');
        final importResult = await _dataProtection.importAfterReinstall();
        if (importResult.success &&
            importResult.importedCount != null &&
            importResult.importedCount! > 0) {
          debugPrint(
              '✅ Imported ${importResult.importedCount} items from previous install');
        }
      }

      // If app was paused for a long time, run integrity check
      if (_lastPauseTime != null) {
        final pauseDuration = DateTime.now().difference(_lastPauseTime!);
        if (pauseDuration > _longPauseThreshold) {
          debugPrint(
              '🔍 Long pause detected (${pauseDuration.inMinutes} min), running integrity check...');
          await _dataProtection.verifyDataIntegrity();
        }
      }
    } catch (e) {
      debugPrint('⚠️ Resume handling failed: $e');
    }
  }

  /// Handle app being terminated
  Future<void> _handleDetached() async {
    try {
      debugPrint('📤 App detaching - exporting for uninstall protection...');

      // Export critical data to external storage
      await _dataProtection.exportForUninstallProtection();

      // Shutdown data protection services
      await _dataProtection.shutdown();
    } catch (e) {
      debugPrint('⚠️ Detach handling failed: $e');
    }
  }
}

/// Mixin for StatefulWidgets that need app lifecycle awareness
mixin AppLifecycleAwareMixin<T extends StatefulWidget> on State<T> {
  late final AppLifecycleObserver _lifecycleObserver;

  /// Override this to provide your DataProtectionService instance
  DataProtectionService get dataProtectionService;

  @override
  void initState() {
    super.initState();
    _lifecycleObserver = AppLifecycleObserver(dataProtectionService);
    _lifecycleObserver.startObserving();
  }

  @override
  void dispose() {
    _lifecycleObserver.stopObserving();
    super.dispose();
  }
}
