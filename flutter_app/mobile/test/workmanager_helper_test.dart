import 'package:flutter_test/flutter_test.dart';
import 'package:workmanager/workmanager.dart';
import 'package:mobile/sync/sync_background.dart';

class _FakeWorkmanager implements Workmanager {
  bool initialized = false;
  bool registered = false;
  Duration? frequency;
  String? registeredTask;

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
      Duration backoffPolicyDelay = const Duration(seconds: 0),
      Constraints? constraints,
      ExistingWorkPolicy? existingWorkPolicy,
      Duration? frequency,
      Duration initialDelay = Duration.zero,
      Map<String, dynamic>? inputData,
      String? tag}) {
    registered = true;
    this.frequency = frequency;
    registeredTask = taskName;
    return Future.value();
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

void main() {
  test('registerBackgroundWork initializes and registers periodic task', () {
    final fake = _FakeWorkmanager();
    registerBackgroundWork(fake);
    expect(fake.initialized, isTrue);
    expect(fake.registered, isTrue);
    expect(fake.registeredTask, equals(syncTaskName));
    expect(fake.frequency, equals(const Duration(hours: 6)));
  });

  test('registerBackgroundWork swallows initialize exceptions', () {
    final bad = _ThrowingWorkmanager();
    expect(() => registerBackgroundWork(bad), returnsNormally);
  });
}
