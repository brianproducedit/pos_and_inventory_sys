import 'package:flutter_test/flutter_test.dart';
import 'package:workmanager/workmanager.dart';
import 'package:mobile/sync/sync_background.dart';
import 'test_helpers.dart';

class _FakeWorkmanager implements Workmanager {
  bool initialized = false;
  bool registered = false;
  Duration? frequency;
  String? registeredTask;
  Constraints? constraints;

  @override
  Future<void> initialize(Function callbackDispatcher,
      {bool isInDebugMode = false}) async {
    initialized = true;
    // we won't call the callbackDispatcher here — tests only assert registration
    return;
  }

  @override
  Future<void> registerPeriodicTask(String uniqueName, String taskName,
      {BackoffPolicy? backoffPolicy,
      Duration? backoffPolicyDelay,
      Constraints? constraints,
      ExistingPeriodicWorkPolicy? existingWorkPolicy,
      Duration? flexInterval,
      ForegroundServiceConfig? foregroundServiceConfig,
      Duration? frequency,
      Duration? initialDelay,
      Map<String, dynamic>? inputData,
      String? tag}) async {
    registered = true;
    this.frequency = frequency;
    registeredTask = taskName;
    this.constraints = constraints;
    return;
  }

  // The Workmanager interface has other methods; we implement minimal surface for tests
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ThrowingWorkmanager extends _FakeWorkmanager {
  @override
  Future<void> initialize(Function callbackDispatcher,
      {bool isInDebugMode = false}) {
    throw Exception('init failed');
  }
}

class _ThrowingRegisterWorkmanager extends _FakeWorkmanager {
  @override
  Future<void> registerPeriodicTask(String uniqueName, String taskName,
      {BackoffPolicy? backoffPolicy,
      Duration? backoffPolicyDelay,
      Constraints? constraints,
      ExistingPeriodicWorkPolicy? existingWorkPolicy,
      Duration? flexInterval,
      ForegroundServiceConfig? foregroundServiceConfig,
      Duration? frequency,
      Duration? initialDelay,
      Map<String, dynamic>? inputData,
      String? tag}) {
    // Simulate failure during registration
    throw Exception('register failed');
  }
}

void main() {
  initializeTestHelpersOnce();

  test('registerBackgroundWork initializes and registers periodic task', () {
    final fake = _FakeWorkmanager();
    registerBackgroundWork(fake);
    expect(fake.initialized, isTrue);
    expect(fake.registered, isTrue);
    expect(fake.registeredTask, equals(syncTaskName));
    expect(fake.frequency, equals(const Duration(hours: 6)));
  });

  test('registerBackgroundWork accepts custom frequency and debug flag', () {
    final fake = _FakeWorkmanager();
    registerBackgroundWork(fake,
        frequency: const Duration(minutes: 15), isInDebugMode: true);
    expect(fake.initialized, isTrue);
    expect(fake.registered, isTrue);
    expect(fake.frequency, equals(const Duration(minutes: 15)));
  });

  test('registerBackgroundWork sets network constraint to connected', () {
    final fake = _FakeWorkmanager();
    registerBackgroundWork(fake);
    expect(fake.initialized, isTrue);
    expect(fake.registered, isTrue);
    expect(fake.constraints, isNotNull);
    expect(fake.constraints!.networkType, equals(NetworkType.connected));
  });

  test('registerBackgroundWork swallows initialize exceptions', () {
    final bad = _ThrowingWorkmanager();
    expect(() => registerBackgroundWork(bad), returnsNormally);
    // If initialize threw, registration should not have been attempted
    expect(bad.registered, isFalse);
  });

  test('registerBackgroundWork swallows registerPeriodicTask exceptions', () {
    final bad = _ThrowingRegisterWorkmanager();
    expect(() => registerBackgroundWork(bad), returnsNormally);
    // Initialization succeeded but registration failed internally
    expect(bad.initialized, isTrue);
    expect(bad.registered, isFalse);
  });
}
