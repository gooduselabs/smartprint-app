import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

final prefsProvider = Provider<SharedPreferences>((_) => throw UnimplementedError());

const _defaultApi = String.fromEnvironment('API_URL', defaultValue: 'http://10.0.2.2:3000');

/// Session: server URL + JWT. Signed out = app still fully usable offline.
class Session {
  const Session({required this.apiUrl, this.token, this.email});
  final String apiUrl;
  final String? token;
  final String? email;
  bool get signedIn => token != null;
}

class SessionController extends Notifier<Session> {
  SharedPreferences get _p => ref.read(prefsProvider);

  @override
  Session build() => Session(apiUrl: _p.getString('apiUrl') ?? _defaultApi, token: _p.getString('token'), email: _p.getString('email'));

  Future<void> setApiUrl(String url) async {
    await _p.setString('apiUrl', url);
    state = Session(apiUrl: url, token: state.token, email: state.email);
  }

  Future<void> authenticate(String email, String password, {required bool register}) async {
    final r = await ref.read(apiProvider).post(register ? '/auth/register' : '/auth/login', data: {'email': email, 'password': password});
    final token = r.data['accessToken'] as String;
    await _p.setString('token', token);
    await _p.setString('email', email);
    state = Session(apiUrl: state.apiUrl, token: token, email: email);
  }

  Future<void> signOut() async {
    await _p.remove('token');
    await _p.remove('email');
    state = Session(apiUrl: state.apiUrl);
  }
}

final sessionProvider = NotifierProvider<SessionController, Session>(SessionController.new);

final apiProvider = Provider<Dio>((ref) {
  final s = ref.watch(sessionProvider);
  return Dio(BaseOptions(
    baseUrl: s.apiUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 90),
    headers: {if (s.token != null) 'Authorization': 'Bearer ${s.token}'},
  ));
});

/// Premium placeholder: no real billing; toggled locally from the paywall.
class PremiumController extends Notifier<bool> {
  @override
  bool build() => ref.read(prefsProvider).getBool('premium') ?? false;
  Future<void> set(bool v) async {
    await ref.read(prefsProvider).setBool('premium', v);
    state = v;
  }
}

final premiumProvider = NotifierProvider<PremiumController, bool>(PremiumController.new);
const freePrintsPerDay = 5;

class PrintJob {
  PrintJob({required this.id, required this.title, required this.kind, required this.pages, required this.printer, required this.printedAt, this.synced = false});
  final String id, title, kind, printer;
  final int pages;
  final DateTime printedAt;
  bool synced;

  Map<String, dynamic> toJson() => {'clientId': id, 'title': title, 'kind': kind, 'pages': pages, 'printer': printer, 'printedAt': printedAt.toUtc().toIso8601String()};
  factory PrintJob.fromJson(Map<String, dynamic> j) => PrintJob(
      id: j['clientId'], title: j['title'], kind: j['kind'], pages: j['pages'] ?? 1, printer: j['printer'] ?? '', printedAt: DateTime.parse(j['printedAt']).toLocal(), synced: j['synced'] ?? false);
}

class HistoryController extends Notifier<List<PrintJob>> {
  SharedPreferences get _p => ref.read(prefsProvider);

  @override
  List<PrintJob> build() {
    final raw = _p.getString('history');
    if (raw == null) return [];
    return (jsonDecode(raw) as List).map((e) => PrintJob.fromJson(e)).toList();
  }

  Future<void> _save() => _p.setString('history', jsonEncode(state.map((j) => {...j.toJson(), 'synced': j.synced}).toList()));

  int get todayCount {
    final now = DateTime.now();
    return state.where((j) => j.printedAt.year == now.year && j.printedAt.month == now.month && j.printedAt.day == now.day).length;
  }

  Future<void> add({required String title, required String kind, required int pages, required String printer}) async {
    state = [PrintJob(id: const Uuid().v4(), title: title, kind: kind, pages: pages, printer: printer, printedAt: DateTime.now()), ...state];
    await _save();
    sync().ignore();
  }

  Future<void> remove(String id) async {
    state = state.where((j) => j.id != id).toList();
    await _save();
  }

  /// Pushes unsynced jobs to the backend when signed in.
  Future<int> sync() async {
    if (!ref.read(sessionProvider).signedIn) return 0;
    final pending = state.where((j) => !j.synced).toList();
    if (pending.isEmpty) return 0;
    await ref.read(apiProvider).post('/jobs/sync', data: {'jobs': pending.map((j) => j.toJson()).toList()});
    for (final j in pending) {
      j.synced = true;
    }
    state = [...state];
    await _save();
    return pending.length;
  }
}

final historyProvider = NotifierProvider<HistoryController, List<PrintJob>>(HistoryController.new);
