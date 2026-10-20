import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

final prefsProvider = Provider<SharedPreferences>((_) => throw UnimplementedError());

class PrintJob {
  PrintJob({required this.id, required this.title, required this.kind, required this.pages, required this.printer, required this.printedAt, this.copies = 1});
  final String id, title, kind, printer;
  final int pages, copies;
  final DateTime printedAt;

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'kind': kind, 'pages': pages, 'copies': copies, 'printer': printer, 'printedAt': printedAt.toUtc().toIso8601String()};
  factory PrintJob.fromJson(Map<String, dynamic> j) => PrintJob(
      id: (j['id'] ?? j['clientId']) as String,
      title: j['title'] as String,
      kind: j['kind'] as String,
      pages: (j['pages'] as int?) ?? 1,
      copies: (j['copies'] as int?) ?? 1,
      printer: (j['printer'] as String?) ?? '',
      printedAt: DateTime.parse(j['printedAt'] as String).toLocal());
}

/// Print history, stored only on this device.
class HistoryController extends Notifier<List<PrintJob>> {
  static const maxEntries = 500;
  SharedPreferences get _p => ref.read(prefsProvider);

  @override
  List<PrintJob> build() {
    final raw = _p.getString('history');
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List).map((e) => PrintJob.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return []; // corrupted store: start fresh rather than crash
    }
  }

  Future<void> _save() => _p.setString('history', jsonEncode(state.map((j) => j.toJson()).toList()));

  Future<void> add({required String title, required String kind, required int pages, required String printer, int copies = 1}) async {
    state = [PrintJob(id: const Uuid().v4(), title: title, kind: kind, pages: pages, copies: copies, printer: printer, printedAt: DateTime.now()), ...state].take(maxEntries).toList();
    await _save();
  }

  Future<void> remove(String id) async {
    state = state.where((j) => j.id != id).toList();
    await _save();
  }

  Future<void> clear() async {
    state = [];
    await _save();
  }
}

final historyProvider = NotifierProvider<HistoryController, List<PrintJob>>(HistoryController.new);
