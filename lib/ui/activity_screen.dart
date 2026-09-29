import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../engine/calc.dart';
import '../engine/models.dart';
import '../services/session.dart';
import 'common.dart';
import 'profile_screen.dart';
import 'result_screen.dart';
import 'track_map.dart';

/// 액티비티 탭: 대기(종목 선택·시작) + 기록 중 화면
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  final s = Session.instance;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    s.addListener(_changed);
    _preview();
  }

  Future<void> _preview() async {
    if (s.active) return;
    await s.ensurePermissions();
    await s.startPreview();
  }

  @override
  void dispose() {
    s.removeListener(_changed);
    s.stopPreview();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _start() async {
    if (_starting) return;
    _starting = true;
    try {
      final err = await s.ensurePermissions();
      if (err != null) {
        _toast(err);
        return;
      }
      if (!s.profileSaved) {
        if (!mounted) return;
        await Navigator.push(context,
            MaterialPageRoute(builder: (_) => const ProfileScreen(first: true)));
        if (!s.profileSaved) {
          _toast('칼로리 계산을 위해 몸무게를 먼저 입력해주세요.');
          return;
        }
      }
      await s.requestBatteryExemption();
      await s.start();
    } finally {
      _starting = false;
    }
  }

  Future<void> _finish() async {
    final tr = s.tracker!;
    final short = tr.liveDistance < 50;
    final choice = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('운동을 종료할까요?'),
        content: Text(short
            ? '이동거리가 50m 미만입니다. 저장하지 않고 버릴 수도 있습니다.'
            : '${km(tr.liveDistance)} km · ${formatDuration(tr.movingSeconds(DateTime.now()))}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('계속하기')),
          if (short)
            TextButton(
                onPressed: () => Navigator.pop(c, 'discard'),
                child: const Text('버리기')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: ink),
              onPressed: () => Navigator.pop(c, 'save'),
              child: const Text('종료 · 저장')),
        ],
      ),
    );
    if (choice == null) return;
    final w = await s.stop(discard: choice == 'discard');
    if (!mounted) return;
    if (w != null) {
      await Navigator.push(
          context, MaterialPageRoute(builder: (_) => ResultScreen(workout: w)));
    }
    s.startPreview();
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final tr = s.tracker;
    final now = DateTime.now();
    final pos = s.lastPosition;
    final current = pos == null ? null : LatLng(pos.latitude, pos.longitude);

    return SafeArea(
      child: Column(children: [
        _statusBar(),
        if (tr == null) _idleStats() else _liveStats(now),
        Expanded(
          child: Stack(children: [
            TrackMap(
              route: tr == null
                  ? const []
                  : tr.track.map((p) => LatLng(p.lat, p.lng)).toList(),
              current: current,
              follow: tr != null,
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 14,
              child: tr == null ? _startPanel() : _controlPanel(),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _statusBar() {
    final tr = s.tracker;
    final acc = tr?.lastAccuracy ?? s.lastPosition?.accuracy;
    String? badge;
    Color badgeColor = ink;
    if (tr != null) {
      if (tr.isPaused) {
        badge = '일시정지';
        badgeColor = muted;
      } else if (tr.isAutoResting) {
        badge = '자동 휴식 중';
        badgeColor = const Color(0xFFF59E0B);
      } else {
        badge = '${s.type.label} 기록 중';
        badgeColor = elevGreen;
      }
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Row(children: [
        if (badge != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            color: badgeColor,
            child: Text(badge,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w800)),
          ),
        const Spacer(),
        _GpsBars(acc),
      ]),
    );
  }

  Widget _idleStats() {
    final sp = (s.lastPosition?.speed ?? 0).clamp(0, 99) * 3.6;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
      child: Column(children: [
        Stat(sp.toStringAsFixed(1), '속도 (KM/시간)', size: 76),
        const SizedBox(height: 22),
        const Row(children: [
          Expanded(child: Stat('0.0', '평균 속도 (KM/시간)')),
          Expanded(child: Stat('0.00', '거리 (KM)')),
          Expanded(child: Stat('00:00', '평균 페이스 (분/KM)')),
        ]),
      ]),
    );
  }

  Widget _liveStats(DateTime now) {
    final tr = s.tracker!;
    final split = tr.currentSplit(now);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
      child: Column(children: [
        Stat(km(tr.liveDistance), '거리 (KM)', size: 76),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
              child: Stat(formatDuration(tr.movingSeconds(now)), '운동 시간',
                  size: 34)),
          Expanded(
              child: Stat(formatPace(tr.avgPaceSecPerKm(now)), '평균 페이스',
                  size: 34)),
          Expanded(
              child: Stat((tr.currentSpeed * 3.6).toStringAsFixed(1),
                  '속도 (KM/시간)',
                  size: 34)),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
              child: Stat(
                  split.distance > 30
                      ? formatPace(split.paceSecPerKm)
                      : '--:--',
                  '${split.index}KM 구간 페이스',
                  size: 26)),
          Expanded(
              child: Stat(tr.avgSpeedKmh(now).toStringAsFixed(1), '평균 속도',
                  size: 26)),
          Expanded(
              child: Stat(tr.kcal.round().toString(), '칼로리', size: 26)),
          Expanded(
              child: Stat('${tr.gain.round()}m', '상승 고도', size: 26)),
        ]),
        if (tr.rests.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            '휴식 ${formatDuration(tr.restSeconds(now))} · 총 경과 ${formatDuration(now.difference(tr.startTime).inSeconds.toDouble())}',
            style: const TextStyle(color: muted, fontSize: 13),
          ),
        ],
      ]),
    );
  }

  Widget _startPanel() {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        for (final t in ActivityType.values) ...[
          Expanded(
            child: _Tile(
              selected: s.type == t,
              onTap: () => s.setType(t),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(activityIcon(t), size: 28),
                const SizedBox(width: 8),
                Text(t.label,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800)),
              ]),
            ),
          ),
          if (t != ActivityType.values.last) const SizedBox(width: 10),
        ],
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: Material(
            color: ink,
            child: InkWell(
              onTap: _start,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                child: Row(children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('시작',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2)),
                    Text(s.type.label,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 16, letterSpacing: 2)),
                  ]),
                  const Spacer(),
                  const Icon(Icons.arrow_right_alt,
                      color: Colors.white, size: 40),
                ]),
              ),
            ),
          ),
        ),
      ]),
    ]);
  }

  Widget _controlPanel() {
    final tr = s.tracker!;
    return Row(children: [
      Expanded(
        child: _Tile(
          selected: false,
          onTap: tr.isPaused ? s.resume : s.pause,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(tr.isPaused ? Icons.play_arrow : Icons.pause, size: 30),
            const SizedBox(width: 6),
            Text(tr.isPaused ? '재개' : '일시정지',
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ]),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Material(
          color: ink,
          child: InkWell(
            onTap: _finish,
            child: const SizedBox(
              height: 60,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.stop, color: Colors.white, size: 30),
                SizedBox(width: 6),
                Text('종료',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800)),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }
}

class _Tile extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  const _Tile(
      {required this.selected, required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: Border.all(
          color: selected ? ink : Colors.white, width: selected ? 2 : 0),
      elevation: selected ? 0 : 1,
      child: InkWell(
          onTap: onTap, child: SizedBox(height: 60, child: child)),
    );
  }
}

/// GPS 신호 막대(정확도 기준)
class _GpsBars extends StatelessWidget {
  final double? accuracy;
  const _GpsBars(this.accuracy);

  @override
  Widget build(BuildContext context) {
    final a = accuracy;
    final level = a == null
        ? 0
        : a <= 8
            ? 3
            : a <= 20
                ? 2
                : 1;
    final color = level >= 2
        ? elevGreen
        : level == 1
            ? const Color(0xFFF59E0B)
            : muted;
    return Row(children: [
      Text('GPS',
          style: TextStyle(
              color: color, fontWeight: FontWeight.w900, letterSpacing: 2)),
      const SizedBox(width: 6),
      for (var i = 1; i <= 3; i++)
        Container(
          width: 5,
          height: 6.0 + i * 5,
          margin: const EdgeInsets.only(left: 2),
          color: i <= level ? color : line,
        ),
    ]);
  }
}
