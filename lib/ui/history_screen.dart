import 'package:flutter/material.dart';

import '../engine/calc.dart';
import '../engine/models.dart';
import '../services/session.dart';
import '../services/storage.dart';
import 'common.dart';
import 'result_screen.dart';

/// 기록 탭: 운동 목록 + 이번 달 합계
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => HistoryScreenState();
}

class HistoryScreenState extends State<HistoryScreen> {
  List<Workout>? _items;

  @override
  void initState() {
    super.initState();
    reload();
    Session.instance.addListener(_onSession);
  }

  @override
  void dispose() {
    Session.instance.removeListener(_onSession);
    super.dispose();
  }

  bool _wasActive = false;
  void _onSession() {
    final a = Session.instance.active;
    if (_wasActive && !a) reload(); // 운동이 끝나면 목록 갱신
    _wasActive = a;
  }

  Future<void> reload() async {
    final list = await Storage.loadWorkouts();
    if (mounted) setState(() => _items = list);
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (items == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final now = DateTime.now();
    final month = items
        .where((w) => w.start.year == now.year && w.start.month == now.month);
    final monthDist = month.fold(0.0, (s, w) => s + w.distance);
    final monthTime = month.fold(0.0, (s, w) => s + w.movingSec);
    final monthKcal = month.fold(0.0, (s, w) => s + w.kcal);

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: reload,
        child: ListView(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
            child: Text('${now.month}월 합계',
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
            child: Row(children: [
              Expanded(child: Stat('${month.length}', '횟수', size: 32)),
              Expanded(child: Stat(km(monthDist, digits: 1), '거리 (KM)', size: 32)),
              Expanded(
                  child: Stat(formatDuration(monthTime, alwaysHours: true),
                      '운동 시간',
                      size: 32)),
              Expanded(
                  child: Stat(monthKcal.round().toString(), '칼로리', size: 32)),
            ]),
          ),
          const Divider(height: 1, color: line),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(
                  child: Text('아직 기록이 없습니다.\n액티비티 탭에서 시작해보세요.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: muted))),
            ),
          for (final w in items) _tile(w),
        ]),
      ),
    );
  }

  Widget _tile(Workout w) {
    return InkWell(
      onTap: () async {
        final deleted = await Navigator.push<bool>(context,
            MaterialPageRoute(builder: (_) => ResultScreen(workout: w)));
        if (deleted == true) reload();
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: line))),
        child: Row(children: [
          Container(
            width: 46,
            height: 46,
            color: ink,
            child: Icon(activityIcon(w.type), color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${dateLabel(w.start)} · ${timeLabel(w.start)}',
                  style: const TextStyle(color: muted, fontSize: 13)),
              const SizedBox(height: 4),
              Text(
                '${w.type.label}  ${km(w.distance)}km',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 2),
              Text(
                '${formatDuration(w.movingSec)} · ${formatPace(w.avgPaceSecPerKm)}/km · ${w.kcal.round()}kcal · ↑${w.gain.round()}m',
                style: const TextStyle(fontSize: 13),
              ),
            ]),
          ),
          const Icon(Icons.chevron_right, color: muted),
        ]),
      ),
    );
  }
}
