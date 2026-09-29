import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../engine/models.dart';

/// 운동 기록은 폰 내부 저장소에 1건당 JSON 파일 하나로 저장
class Storage {
  static Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/workouts');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  static Future<void> saveWorkout(Workout w) async {
    final d = await _dir();
    await File('${d.path}/${w.id}.json').writeAsString(jsonEncode(w.toJson()));
  }

  static Future<void> deleteWorkout(String id) async {
    final f = File('${(await _dir()).path}/$id.json');
    if (f.existsSync()) await f.delete();
  }

  static Future<List<Workout>> loadWorkouts() async {
    final d = await _dir();
    final list = <Workout>[];
    for (final f in d.listSync().whereType<File>()) {
      if (!f.path.endsWith('.json')) continue;
      try {
        list.add(Workout.fromJson(
            jsonDecode(await f.readAsString()) as Map<String, dynamic>));
      } catch (_) {
        // 손상된 파일은 건너뜀
      }
    }
    list.sort((a, b) => b.start.compareTo(a.start));
    return list;
  }

  // ── 진행 중 운동 백업(앱이 강제 종료돼도 복구) ─────────
  static Future<File> _liveFile() async =>
      File('${(await getApplicationDocumentsDirectory()).path}/live.jsonl');

  static IOSink? _sink;

  static Future<void> liveBegin(Map<String, dynamic> header) async {
    final f = await _liveFile();
    _sink = f.openWrite();
    _sink!.writeln(jsonEncode(header));
  }

  static void liveAppend(Map<String, dynamic> event) {
    _sink?.writeln(jsonEncode(event));
  }

  static Future<void> liveFlush() async => _sink?.flush();

  static Future<void> liveEnd() async {
    await _sink?.flush();
    await _sink?.close();
    _sink = null;
    final f = await _liveFile();
    if (f.existsSync()) await f.delete();
  }

  static Future<List<Map<String, dynamic>>?> liveRead() async {
    final f = await _liveFile();
    if (!f.existsSync()) return null;
    final out = <Map<String, dynamic>>[];
    for (final line in await f.readAsLines()) {
      if (line.trim().isEmpty) continue;
      try {
        out.add(jsonDecode(line) as Map<String, dynamic>);
      } catch (_) {
        break; // 마지막 줄이 쓰다 끊긴 경우
      }
    }
    return out.isEmpty ? null : out;
  }

  static Future<void> liveDiscard() async {
    final f = await _liveFile();
    if (f.existsSync()) await f.delete();
  }

  // ── 신체 정보 ────────────────────────────────────
  static Future<Profile?> loadProfile() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString('profile');
    if (s == null) return null;
    return Profile.fromJson(jsonDecode(s) as Map<String, dynamic>);
  }

  static Future<void> saveProfile(Profile profile) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('profile', jsonEncode(profile.toJson()));
  }
}
