import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynveris/store.dart';

class MemoryStorage implements KeyValueStorage {
  final data = <String, String>{};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async {
    data[key] = value;
  }
}

class BrokenStorage implements KeyValueStorage {
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> write(String key, String value) async =>
      throw StateError('disk unavailable');
}

Map<String, dynamic> result() => {
  'id': 'test',
  'checked_at': DateTime.now().toUtc().toIso8601String(),
  'title': 'Chưa đủ thông tin',
  'verdict': 'insufficient',
  'url': {
    'original':
        'https://user:secret@example.com/private-token?token=secret#frag',
    'hostname': 'example.com',
    'unicode_hostname': 'example.com',
    'scheme': 'https',
  },
  'signals': <dynamic>[],
  'threat': {'source': 'Google Safe Browsing', 'status': 'skipped'},
  'model': {'status': 'unavailable'},
  'limitations': <dynamic>[],
  'actions': <dynamic>[],
  'summary': 'Chưa kiểm tra đủ',
};

void main() {
  test('storage failure is visible and does not prevent checks', () async {
    final store = AppStore(BrokenStorage());
    await store.load();
    expect(store.storageError, isNotNull);
    expect(store.saveHistory, isFalse);
    expect(store.deletionToken.length, 64);
  });
  test('history opt-in, redaction, persistence and deletion', () async {
    final storage = MemoryStorage();
    final store = AppStore(storage);
    await store.load();
    final response = result()
      ..['signals'] = [
        {'code': 'embedded_destination', 'detail': 'private.internal.example'},
      ];
    await store.addResult(response);
    expect(store.history, isEmpty);
    await store.setHistory(true);
    await store.addResult(response);
    expect(store.history.length, 1);
    expect(jsonEncode(storage.data), isNot(contains('secret')));
    expect(jsonEncode(storage.data), isNot(contains('private-token')));
    expect(
      jsonEncode(storage.data),
      isNot(contains('private.internal.example')),
    );
    final reloaded = AppStore(storage);
    await reloaded.load();
    expect(reloaded.history.length, 1);
    await reloaded.deleteItem('test');
    expect(reloaded.history, isEmpty);
    await store.setHistory(false);
    expect(store.history, isEmpty);
  });
  test(
    'switching server keeps research ownership scoped to its server',
    () async {
      final storage = MemoryStorage();
      final store = AppStore(storage);
      await store.load();
      final previous = store.apiBase;
      final previousToken = store.deletionToken;
      store.researchConsent = true;
      await store.setServer('https://second.example');
      expect(store.researchConsent, isFalse);
      expect(store.deletionToken, isNot(previousToken));
      final restarted = AppStore(storage);
      await restarted.load();
      expect(restarted.deletionToken, store.deletionToken);
      await restarted.setServer(previous);
      expect(restarted.deletionToken, previousToken);
    },
  );
  test('expired entries are removed', () async {
    final storage = MemoryStorage();
    final old = result()..['checked_at'] = DateTime(2020).toIso8601String();
    storage.data['history'] = jsonEncode([old]);
    final store = AppStore(storage);
    await store.load();
    expect(store.history, isEmpty);
  });
}
