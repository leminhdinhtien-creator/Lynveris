import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'build_config.dart';

abstract class KeyValueStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class DeviceStorage implements KeyValueStorage {
  final _preferences = SharedPreferencesAsync();
  @override
  Future<String?> read(String key) => _preferences.getString('lynveris_$key');
  @override
  Future<void> write(String key, String value) =>
      _preferences.setString('lynveris_$key', value);
}

class AppStore extends ChangeNotifier {
  AppStore(this.storage);
  final KeyValueStorage storage;
  bool onboardingDone = false,
      saveHistory = false,
      useThreat = false,
      researchConsent = false;
  double textScale = 1;
  String apiBase = defaultApiBase;
  String deletionToken = '';
  final _serverTokens = <String, String>{};
  List<Map<String, dynamic>> history = [];
  String? storageError;
  Future<void> _writes = Future<void>.value();

  Future<void> load() async {
    try {
      final settings =
          jsonDecode(await storage.read('settings') ?? '{}') as Map;
      onboardingDone = settings['onboarding'] == true;
      saveHistory = settings['history'] == true;
      useThreat = settings['threat'] == true;
      researchConsent = settings['research'] == true;
      textScale = ((settings['textScale'] as num?)?.toDouble() ?? 1).clamp(
        1,
        1.5,
      );
      final saved = settings['api'];
      if (!fixedServer) {
        if (saved is String &&
            (allowDevelopmentHttp || Uri.tryParse(saved)?.scheme == 'https')) {
          apiBase = saved;
        }
      }
      final tokens = settings['serverTokens'];
      if (tokens is Map) {
        for (final entry in tokens.entries) {
          if (entry.key is String && entry.value is String) {
            _serverTokens[entry.key] = entry.value;
          }
        }
      }
      final previousToken = settings['deletionToken'];
      final previousServer = saved is String ? saved : apiBase;
      if (previousToken is String && previousToken.isNotEmpty) {
        _serverTokens.putIfAbsent(
          _serverKey(previousServer),
          () => previousToken,
        );
      }
      deletionToken = _serverTokens[_serverKey(apiBase)] ?? '';
      if (_serverKey(previousServer) != _serverKey(apiBase)) {
        researchConsent = false;
      }
      final stored = jsonDecode(await storage.read('history') ?? '[]') as List;
      final cutoff = DateTime.now().subtract(const Duration(days: 30));
      history = saveHistory
          ? stored
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .where(
                  (e) =>
                      (DateTime.tryParse(e['checked_at'] ?? '') ??
                              DateTime(2000))
                          .isAfter(cutoff),
                )
                .take(100)
                .map(_redactHistory)
                .toList()
          : [];
    } catch (_) {
      history = [];
    }
    if (deletionToken.isEmpty) {
      deletionToken = _newToken();
    }
    await persist();
  }

  Future<void> persist() async {
    if (deletionToken.isNotEmpty) {
      _serverTokens[_serverKey(apiBase)] = deletionToken;
    }
    final settings = jsonEncode({
      'onboarding': onboardingDone,
      'history': saveHistory,
      'threat': useThreat,
      'research': researchConsent,
      'textScale': textScale,
      'api': apiBase,
      'deletionToken': deletionToken,
      'serverTokens': _serverTokens,
    });
    final entries = jsonEncode(history);
    notifyListeners();
    _writes = _writes.then((_) async {
      try {
        await storage.write('settings', settings);
        await storage.write('history', entries);
        storageError = null;
      } catch (_) {
        storageError = 'Chưa lưu được thay đổi trên thiết bị. Dữ liệu có thể không còn sau khi đóng ứng dụng.';
      }
      notifyListeners();
    });
    await _writes;
  }

  Future<void> setServer(String value) async {
    if (fixedServer) return;
    final previousKey = _serverKey(apiBase);
    final nextKey = _serverKey(value);
    if (nextKey != previousKey) {
      _serverTokens[previousKey] = deletionToken;
      deletionToken = _serverTokens[nextKey] ?? _newToken();
      researchConsent = false;
    }
    apiBase = value;
    await persist();
  }

  Future<void> setHistory(bool value) async {
    saveHistory = value;
    if (!value) {
      history.clear();
    }
    await persist();
  }

  Future<void> addResult(Map<String, dynamic> result) async {
    if (!saveHistory) {
      return;
    }
    final copy = _redactHistory(result);
    history = [copy, ...history.where((e) => e['id'] != copy['id'])]
        .where(
          (e) => (DateTime.tryParse(e['checked_at'] ?? '') ?? DateTime(2000))
              .isAfter(DateTime.now().subtract(const Duration(days: 30))),
        )
        .take(100)
        .toList();
    await persist();
  }

  Future<void> deleteItem(String id) async {
    history.removeWhere((e) => e['id'] == id);
    await persist();
  }

  Future<void> clearHistory() async {
    history.clear();
    await persist();
  }
}

String _serverKey(String value) => value.trim().replaceAll(RegExp(r'/+$'), '');

String _newToken() {
  final random = Random.secure();
  return List.generate(
    32,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

Map<String, dynamic> _redactHistory(Map<String, dynamic> result) {
  final copy = Map<String, dynamic>.of(result);
  final url = Map<String, dynamic>.from(copy['url']);
  final host = url['hostname'] as String;
  url['original'] =
      '${url['scheme']}://${host.contains(':') ? '[$host]' : host}/';
  copy['url'] = url;
  final signals = copy['signals'];
  if (signals is List) {
    copy['signals'] = signals
        .where((s) => s is Map && s['code'] != 'embedded_destination')
        .toList();
  }
  copy['history_redacted'] = true;
  return copy;
}
