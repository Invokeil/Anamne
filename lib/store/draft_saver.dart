import 'dart:async';

import 'package:flutter/material.dart';

/// Serializes immutable draft snapshots. Navigation flushes the captured ID,
/// never controllers belonging to whichever document is displayed next.
class DraftSaver<T> extends ChangeNotifier {
  DraftSaver(this._save, {this.delay = const Duration(milliseconds: 400)});

  final Future<void> Function(T) _save;
  final Duration delay;
  Timer? _timer;
  T? _pending;
  bool _hasPending = false;
  bool _disposed = false;
  Future<void>? _inFlight;
  Object? error;

  bool get hasPending => _hasPending;
  bool get isSaving => _inFlight != null;

  void _notify() { if (!_disposed) notifyListeners(); }

  void schedule(T snapshot) {
    if (_disposed) return;
    _pending = snapshot;
    _hasPending = true;
    error = null;
    _timer?.cancel();
    _timer = Timer(delay, () => unawaited(flush()));
    _notify();
  }

  Future<void> flush() {
    _timer?.cancel();
    return _inFlight ??= Future<void>.microtask(_drain).whenComplete(() {
      _inFlight = null;
      _notify();
    });
  }

  Future<void> _drain() async {
    _notify();
    while (_hasPending) {
      final snapshot = _pending as T;
      _hasPending = false;
      try {
        await _save(snapshot);
        error = null;
      } catch (failure) {
        if (!_hasPending) { _pending = snapshot; _hasPending = true; }
        error = failure;
        break;
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_hasPending) unawaited(flush());
    _disposed = true;
    super.dispose();
  }
}

class DraftSaveStatus<T> extends StatelessWidget {
  const DraftSaveStatus({super.key, required this.saver});
  final DraftSaver<T> saver;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: saver,
    builder: (context, _) => Row(mainAxisSize: MainAxisSize.min, children: [
      Text(saver.error != null ? 'Save failed — draft pending'
          : saver.isSaving ? 'Saving…' : saver.hasPending ? 'Unsaved changes' : 'Saved locally',
          style: TextStyle(fontSize: 12, color: saver.error != null
              ? Theme.of(context).colorScheme.error : Theme.of(context).hintColor)),
      if (saver.error != null) TextButton(onPressed: () => unawaited(saver.flush()),
          child: const Text('Retry')),
    ]),
  );
}
