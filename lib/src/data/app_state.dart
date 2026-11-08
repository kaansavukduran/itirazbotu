/// Ayarlar ve geçmiş: yalnızca cihazdaki JSON dosyalarında tutulur.
///
/// Hesap, telemetri ya da eşitleme yoktur. Geçmiş varsayılan olarak kapalıdır.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

class AppSettings extends ChangeNotifier {
  AppSettings(this._file);

  final File _file;

  ThemeMode themeMode = ThemeMode.system;
  bool largeText = false;
  bool historyEnabled = false;
  String? activeModelPath;

  Future<void> load() async {
    try {
      if (!_file.existsSync()) return;
      final j = jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
      themeMode = ThemeMode.values.firstWhere((m) => m.name == j['theme'], orElse: () => ThemeMode.system);
      largeText = j['largeText'] == true;
      historyEnabled = j['history'] == true;
      activeModelPath = j['activeModel'] as String?;
    } catch (_) {
      // Bozuk ayar dosyası varsayılanlarla devam eder.
    }
  }

  Future<void> _save() async {
    try {
      await _file.parent.create(recursive: true);
      await _file.writeAsString(jsonEncode({
        'theme': themeMode.name,
        'largeText': largeText,
        'history': historyEnabled,
        'activeModel': activeModelPath,
      }));
    } catch (_) {}
  }

  Future<void> update({ThemeMode? theme, bool? large, bool? history, String? model, bool clearModel = false}) async {
    if (theme != null) themeMode = theme;
    if (large != null) largeText = large;
    if (history != null) historyEnabled = history;
    if (model != null) activeModelPath = model;
    if (clearModel) activeModelPath = null;
    notifyListeners();
    await _save();
  }
}

class HistoryEntry {
  HistoryEntry({required this.time, required this.input, required this.outcome, required this.mode});

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
        time: DateTime.tryParse(j['t'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
        input: j['i'] as String? ?? '',
        outcome: j['o'] as String? ?? '',
        mode: j['m'] as String? ?? '',
      );

  final DateTime time;
  final String input;
  final String outcome;
  final String mode;

  Map<String, dynamic> toJson() => {'t': time.toIso8601String(), 'i': input, 'o': outcome, 'm': mode};
}

class HistoryStore extends ChangeNotifier {
  HistoryStore(this._file);

  final File _file;
  static const int maxEntries = 200;
  final List<HistoryEntry> _entries = [];
  List<HistoryEntry> get entries => List.unmodifiable(_entries);

  Future<void> load() async {
    _entries.clear();
    try {
      if (_file.existsSync()) {
        final list = jsonDecode(await _file.readAsString()) as List;
        _entries.addAll(list.whereType<Map<String, dynamic>>().map(HistoryEntry.fromJson));
      }
    } catch (_) {}
    notifyListeners();
  }

  /// Yalnızca geçmiş açıksa çağrılmalı; [enabled] bunu ikinci kez güvenceye alır.
  Future<void> add(HistoryEntry e, {required bool enabled}) async {
    if (!enabled) return;
    _entries.insert(0, e);
    if (_entries.length > maxEntries) _entries.removeRange(maxEntries, _entries.length);
    notifyListeners();
    try {
      await _file.parent.create(recursive: true);
      await _file.writeAsString(jsonEncode(_entries.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  /// Tek dokunuşla temizleme: bellek ve dosya birlikte silinir.
  Future<void> clear() async {
    _entries.clear();
    notifyListeners();
    try {
      if (_file.existsSync()) await _file.delete();
    } catch (_) {}
  }
}
