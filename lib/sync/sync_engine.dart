import 'dart:async';

import 'package:flutter/foundation.dart';

import '../store/page_repository.dart';
import 'api_client.dart';

enum SyncPhase { disabled, offline, syncing, idle, error }

class SyncStatus {
  const SyncStatus({
    this.phase = SyncPhase.disabled,
    this.lastSyncedAt,
    this.message,
    this.pendingOps = 0,
  });

  final SyncPhase phase;
  final DateTime? lastSyncedAt;
  final String? message;
  final int pendingOps;

  SyncStatus copyWith({SyncPhase? phase, DateTime? lastSyncedAt, String? message, int? pendingOps}) =>
      SyncStatus(
        phase: phase ?? this.phase,
        lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
        message: message,
        pendingOps: pendingOps ?? this.pendingOps,
      );

  String get label {
    switch (phase) {
      case SyncPhase.disabled:
        return 'Local only';
      case SyncPhase.offline:
        return 'Offline · retrying';
      case SyncPhase.syncing:
        return 'Syncing…';
      case SyncPhase.error:
        return message == null ? 'Sync error' : 'Sync: $message';
      case SyncPhase.idle:
        final pending = pendingOps > 0 ? ' · $pendingOps pending' : '';
        if (lastSyncedAt == null) return 'Connected$pending';
        final local = lastSyncedAt!.toLocal();
        return 'Synced ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}$pending';
    }
  }
}

/// Offline-first sync engine.
///
/// Every local mutation is written to the durable outbox in the same
/// transaction as the record itself. [runOnce] drains the outbox to
/// `POST /v1/sync/push`, then pulls server changes since the stored cursor.
/// The server is authoritative for canonical updated_at; a conflicting
/// remote snapshot wins while the local edit is preserved as a conflict copy.
class SyncEngine {
  SyncEngine(this._repository, {
    AnamneApi Function(String, String)? apiFactory,
    this.periodic = true,
  }) : _apiFactory = apiFactory ?? ((url, token) => AnamneApi(baseUrl: url, token: token));

  final PageRepository _repository;
  final AnamneApi Function(String, String) _apiFactory;
  final bool periodic;
  bool _disposed = false;
  int _epoch = 0;
  final ValueNotifier<int> changes = ValueNotifier(0);
  AnamneApi? _api;
  Timer? _timer;
  bool _running = false;

  final ValueNotifier<SyncStatus> status =
      ValueNotifier(const SyncStatus());

  static const interval = Duration(seconds: 15);
  static const batchSize = 50;

  bool get enabled => _api != null;

  Future<void> configure({String? serverUrl, String? token}) async {
    if (serverUrl == null || serverUrl.trim().isEmpty || token == null || token.trim().isEmpty) {
      await disable();
      return;
    }
    final url = serverUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(url);
    if (uri == null || !['https', 'http'].contains(uri.scheme) || uri.host.isEmpty ||
        uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
      throw ArgumentError('Enter an http(s) server URL without credentials, query or fragment');
    }
    final previous = await _repository.setting('serverUrl') as String?;
    if (previous != null && previous.replaceFirst(RegExp(r'/+$'), '') != url) {
      throw StateError('This local workspace is bound to another server. Export a backup and use a separate local workspace before switching.');
    }
    _epoch++;
    _api?.close();
    _api = _apiFactory(url, token.trim());
    await _repository.setSetting('syncEnabled', true);
    await _repository.setSetting('serverUrl', url);
    await _repository.setSetting('token', token.trim());
    _startTimer();
  }

  Future<void> disable() async {
    _epoch++;
    _api?.close();
    _api = null;
    _timer?.cancel();
    _timer = null;
    await _repository.setSetting('syncEnabled', false);
    status.value = const SyncStatus(phase: SyncPhase.disabled);
  }

  /// Restores a previously configured sync connection, if any.
  Future<void> restoreFromSettings() async {
    final enabledSetting = await _repository.setting('syncEnabled') == true;
    if (!enabledSetting) {
      status.value = const SyncStatus(phase: SyncPhase.disabled);
      return;
    }
    final url = await _repository.setting('serverUrl') as String?;
    final token = await _repository.setting('token') as String?;
    if (url == null || token == null) {
      status.value = const SyncStatus(phase: SyncPhase.disabled);
      return;
    }
    _api = _apiFactory(url, token);
    unawaited(runOnce());
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    if (periodic) _timer = Timer.periodic(interval, (_) => unawaited(runOnce()));
  }

  Future<bool> testConnection() async {
    final api = _api;
    if (api == null) return false;
    try {
      await api.health();
      return true;
    } on AnamneApiException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> runOnce() async {
    final api = _api;
    if (api == null || _running || _disposed) return;
    final epoch = _epoch;
    _running = true;
    try {
      status.value = status.value.copyWith(phase: SyncPhase.syncing);
      final rejection = await _pushOutbox(api);
      if (_disposed || epoch != _epoch) return;
      await _pullChanges(api);
      if (_disposed || epoch != _epoch) return;
      changes.value++;
      status.value = SyncStatus(
        phase: rejection == null ? SyncPhase.idle : SyncPhase.error,
        lastSyncedAt: rejection == null ? DateTime.now() : status.value.lastSyncedAt,
        message: rejection,
        pendingOps: await _repository.outboxCount(),
      );
    } on AnamneApiException catch (error) {
      if (!_disposed && epoch == _epoch) status.value = status.value.copyWith(
        phase: error.isAuth ? SyncPhase.error : SyncPhase.offline, message: error.message);
    } catch (error) {
      if (!_disposed && epoch == _epoch) status.value = status.value.copyWith(
        phase: SyncPhase.offline, message: error.toString());
    } finally { _running = false; }
  }

  Future<String?> _pushOutbox(AnamneApi api) async {
    final blocked = <String>{};
    String? rejection;
    // Bounded work per pass. Rejected operations retry on the next timer tick,
    // never in an unbounded hot loop that prevents pulling remote changes.
    for (var batch = 0; batch < 4; batch++) {
      final queued = await _repository.outboxOps(limit: 1000);
      final selected = <Map<String, Object?>>[];
      final seen = <String>{};
      for (final op in queued) {
        final key = '${op['entity']}:${op['targetId']}';
        if (blocked.contains(key) || !seen.add(key)) continue;
        selected.add(op);
        if (selected.length == batchSize) break;
      }
      if (selected.isEmpty) break;
      final result = await api.push(selected);
      final results = (result['results'] as List<Object?>? ?? const [])
          .whereType<Map<String, Object?>>();
      final byOpId = {for (final r in results) r['opId'] as String: r};
      for (final op in selected) {
        final opId = op['opId'] as String;
        final entity = op['entity'] as String;
        final target = op['targetId'] as String;
        final outcome = byOpId[opId];
        switch (outcome?['status']) {
          case 'applied':
          case 'noop':
            await _repository.acknowledgeOutbox(opId, (outcome?['version'] as num?)?.toInt());
          case 'conflict':
            await _repository.resolveConflict(entity, target,
                outcome?['server'] as Map<String, Object?>?);
          default:
            final message = outcome?['message'] as String? ?? 'No valid acknowledgement from server';
            await _repository.markOutboxAttempt(opId, message);
            blocked.add('$entity:$target');
            rejection ??= message;
        }
      }
    }
    return rejection;
  }

  Future<void> _pullChanges(AnamneApi api) async {
    var cursor = ((await _repository.setting('syncCursor')) as num?)?.toInt() ?? 0;
    while (true) {
      final page = await api.pull(cursor: cursor);
      final changes = (page['changes'] as List<Object?>? ?? const [])
          .whereType<Map<String, Object?>>()
          .toList();
      for (final change in changes) {
        final entity = change['entity'] as String?;
        final id = change['id'] as String?;
        if (id == null) continue;
        if (change['op'] == 'delete') {
          if (entity == 'database') {
            await _repository.deleteDatabaseFromServer(id);
          } else {
            await _repository.deleteFromServer(id);
          }
          continue;
        }
        if (entity == 'database') {
          final record = change['database'] as Map<String, Object?>?;
          if (record != null) await _repository.upsertDatabaseFromServer(record);
        } else {
          final record = change['page'] as Map<String, Object?>?;
          if (record != null) await _repository.upsertFromServer(record);
        }
      }
      final nextCursor = (page['cursor'] as num?)?.toInt() ?? cursor;
      final more = page['more'] == true;
      await _repository.setSetting('syncCursor', nextCursor);
      cursor = nextCursor;
      if (!more || changes.isEmpty) return;
    }
  }

  void dispose() {
    _disposed = true;
    _epoch++;
    _timer?.cancel();
    _api?.close();
    changes.dispose();
    status.dispose();
  }
}
