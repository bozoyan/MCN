import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/services/document_save_coordinator.dart';

void main() {
  test('debounces edits and saves only the latest snapshot', () async {
    final saved = <String>[];
    final coordinator = DocumentSaveCoordinator<String>(
      debounce: const Duration(milliseconds: 20),
      save: (snapshot) async => saved.add(snapshot),
    );
    addTearDown(coordinator.dispose);

    coordinator
      ..schedule('first')
      ..schedule('latest');
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(saved, ['latest']);
    expect(coordinator.isDirty, isFalse);
  });

  test('serializes an edit that arrives during an in-flight save', () async {
    final firstSave = Completer<void>();
    final started = Completer<void>();
    final saved = <String>[];
    final coordinator = DocumentSaveCoordinator<String>(
      debounce: const Duration(hours: 1),
      save: (snapshot) async {
        saved.add(snapshot);
        if (snapshot == 'first') {
          started.complete();
          await firstSave.future;
        }
      },
    );
    addTearDown(coordinator.dispose);

    coordinator.schedule('first');
    final flush = coordinator.flush();
    await started.future;
    coordinator.schedule('second');
    firstSave.complete();
    await flush;

    expect(saved, ['first', 'second']);
    expect(coordinator.isDirty, isFalse);
  });

  test('retains a failed snapshot and retry clears the error', () async {
    var attempts = 0;
    final coordinator = DocumentSaveCoordinator<String>(
      debounce: const Duration(hours: 1),
      save: (_) async {
        attempts += 1;
        if (attempts == 1) throw StateError('offline');
      },
    );
    addTearDown(coordinator.dispose);

    coordinator.schedule('draft');
    await expectLater(coordinator.flush(), throwsStateError);
    expect(coordinator.isDirty, isTrue);
    expect(coordinator.lastError, isA<StateError>());

    await coordinator.retry();

    expect(attempts, 2);
    expect(coordinator.isDirty, isFalse);
    expect(coordinator.lastError, isNull);
  });
}
