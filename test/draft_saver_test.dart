import 'dart:async';

import 'package:anamne/store/draft_saver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('navigation flushes the captured draft before its debounce expires', () async {
    final saved = <String>[];
    final saver = DraftSaver<String>((snapshot) async { saved.add(snapshot); },
        delay: const Duration(days: 1));
    saver.schedule('page-A: বাংলা draft');
    saver.dispose();
    await saver.flush();
    expect(saved, ['page-A: বাংলা draft']);
  });

  test('a newer snapshot waits for an in-flight save and remains last', () async {
    final first = Completer<void>();
    final saved = <String>[];
    final saver = DraftSaver<String>((snapshot) async {
      saved.add(snapshot);
      if (snapshot == 'first') await first.future;
    }, delay: const Duration(days: 1));
    saver.schedule('first');
    final flushing = saver.flush();
    await Future<void>.delayed(Duration.zero);
    saver.schedule('latest');
    first.complete();
    await flushing;
    expect(saved, ['first', 'latest']);
    expect(saver.hasPending, isFalse);
    saver.dispose();
  });

  test('storage failure keeps the draft available for retry', () async {
    var fail = true;
    String? saved;
    final saver = DraftSaver<String>((snapshot) async {
      if (fail) throw StateError('synthetic full disk');
      saved = snapshot;
    }, delay: const Duration(days: 1));
    saver.schedule('recover me');
    await saver.flush();
    expect(saver.error, isA<StateError>());
    expect(saver.hasPending, isTrue);
    fail = false;
    await saver.flush();
    expect(saved, 'recover me');
    expect(saver.error, isNull);
    saver.dispose();
  });
}
