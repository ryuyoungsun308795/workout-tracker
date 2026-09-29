import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../engine/calc.dart';
import '../engine/models.dart';
import '../services/storage.dart';
import 'common.dart';
import 'track_map.dart';

/// 운동 1건 결과: 지도 / 그래프 / 스플릿
class ResultScreen extends StatelessWidget {
  final Workout workout;
  const ResultScreen({super.key, required this.workout});

  Future<void> _delete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('이 기록을 삭제할까요?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('취소')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('삭제', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    await Storage.deleteWorkout(workout.id);
    if (context.mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final w = workout;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: Text('${dateLabel(w.start)} ${w.type.label}',
              style: const TextStyle(
                  fontWeight: FontWeight.w800, letterSpacing: 1)),
          actions: [
            IconButton(
                onPressed: () => _delete(context),
                icon: const Icon(Icons.delete_outline)),
          ],
          bottom: const TabBar(
            indicatorColor: ink,
            indicatorWeight: 3,
            labelColor: ink,
            unselectedLabelColor: Color(0xFFAAAAAA),
            tabs: [
              Tab(icon: Icon(Icons.map_outlined, size: 30)),
              Tab(icon: Icon(Icons.show_chart, size: 30)),
              Tab(icon: Icon(Icons.bar_chart, size: 30)),
            ],
          ),
        ),
        body: TabBarView(
          physics: const NeverScrollableScrollPhysics(), // 지도 드래그와 충돌 방지
          children: [
            _SummaryTab(w),
            _GraphTab(w),
            _SplitsTab(w),
          ],
        ),
      ),
    );
  }
}

// ── 지도 + 요약 ────────────────────────────────────────
class _SummaryTab extends StatelessWidget {
  final Workout w;
  const _SummaryTab(this.w);

  @override
  Widget build(BuildContext context) {
    final route = w.track.map((p) => LatLng(p.lat, p.lng)).toList();
    final full = w.splits.where((s) => s.distance >= 1000).toList();
    final best = full.isEmpty
        ? null
        : full.reduce((a, b) => a.paceSecPerKm <= b.paceSecPerKm ? a : b);
    final range = (w.maxAlt != null && w.minAlt != null)
        ? w.maxAlt! - w.minAlt!
        : null;
    final p = w.profile;

    return ListView(children: [
      SizedBox(
        height: 320,
        child: route.isEmpty
            ? const Center(child: Text('기록된 경로가 없습니다'))
            : TrackMap(route: route, fitRoute: true, showStartEnd: true),
      ),
      Container(
        color: const Color(0xFFF1F2F4),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Row(children: [
          Icon(activityIcon(w.type)),
          const SizedBox(width: 8),
          Text(w.type.label,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
        child: Row(children: [
          Expanded(
              child: Stat(km(w.distance), '거리 (KM)',
                  size: 38, align: CrossAxisAlignment.start)),
          Expanded(
              flex: 2,
              child: Stat(formatDuration(w.movingSec, alwaysHours: true),
                  '운동 시간',
                  size: 38, align: CrossAxisAlignment.start)),
          Expanded(
              child: Stat(w.kcal.round().toString(), '칼로리',
                  size: 38, align: CrossAxisAlignment.start)),
        ]),
      ),
      const Divider(height: 1, color: line),
      InfoRow(Icons.timer_outlined, '평균 페이스',
          '${formatPace(w.avgPaceSecPerKm)} 분/km'),
      InfoRow(Icons.speed, '평균 속도',
          '${w.avgSpeedKmh.toStringAsFixed(1)} km/시간'),
      InfoRow(Icons.bolt, '최대 속도',
          '${(w.maxSpeed * 3.6).toStringAsFixed(1)} km/시간'),
      if (best != null)
        InfoRow(Icons.emoji_events_outlined, '최고 1km 구간',
            '${best.index}km · ${formatPace(best.paceSecPerKm)}'),
      InfoRow(Icons.trending_up, '상승 고도', '${w.gain.round()} 미터'),
      InfoRow(Icons.trending_down, '하강 고도', '${w.loss.round()} 미터'),
      if (w.maxAlt != null)
        InfoRow(Icons.landscape_outlined, '최고 고도', '${w.maxAlt!.round()} 미터'),
      if (w.minAlt != null)
        InfoRow(Icons.water_outlined, '최저 고도', '${w.minAlt!.round()} 미터'),
      if (range != null)
        InfoRow(Icons.height, '고저차', '${range.round()} 미터'),
      InfoRow(Icons.local_fire_department_outlined, '소모 칼로리',
          '${w.kcal.round()} kcal'),
      InfoRow(Icons.self_improvement, '휴식 시간',
          '${formatDuration(w.restSec)} (${w.rests.length}회)'),
      InfoRow(Icons.hourglass_bottom, '총 경과 시간',
          formatDuration(w.end.difference(w.start).inSeconds.toDouble(),
              alwaysHours: true)),
      InfoRow(Icons.schedule, '시작 시간', timeLabel(w.start)),
      InfoRow(Icons.flag_outlined, '종료 시간', timeLabel(w.end)),
      InfoRow(Icons.accessibility_new, '신체',
          '${p.heightCm.round()}cm · ${p.weightKg.toStringAsFixed(1)}kg · 허리 ${p.waistCm.round()}cm'),
      InfoRow(Icons.monitor_weight_outlined, 'BMI', p.bmi.toStringAsFixed(1)),
      const SizedBox(height: 30),
    ]);
  }
}

// ── 그래프(페이스 + 고도) ──────────────────────────────
class _GraphTab extends StatelessWidget {
  final Workout w;
  const _GraphTab(this.w);

  @override
  Widget build(BuildContext context) {
    final pace = paceSeries(w);
    final elev = [
      for (final p in w.track)
        if (p.alt != null) Offset(p.distance, p.alt!)
    ];
    return Column(children: [
      const SizedBox(height: 18),
      Text('전체: ${km(w.distance)} KM',
          style: const TextStyle(
              fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2)),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
        child: Row(children: [
          Expanded(
              child: _Legend(formatPace(w.avgPaceSecPerKm), '분/KM', '평균 페이스',
                  paceBlue)),
          Expanded(
              child: _Legend('${w.gain.round()}', '미터', '상승 고도', elevGreen)),
          Expanded(
              child: _Legend(
                  w.maxAlt == null ? '-' : '${w.maxAlt!.round()}',
                  '미터',
                  '최고 고도',
                  elevGreen)),
        ]),
      ),
      const Divider(height: 1, color: line),
      Expanded(
        child: pace.length < 2 && elev.length < 2
            ? const Center(child: Text('그래프를 그리기엔 기록이 짧습니다'))
            : Padding(
                padding: const EdgeInsets.only(top: 8),
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _ChartPainter(
                    pace: pace,
                    elev: elev,
                    totalDist: w.distance,
                    avgPace: w.avgPaceSecPerKm,
                  ),
                ),
              ),
      ),
    ]);
  }
}

/// 거리 구간별 페이스 (x = 거리 m, y = 초/km)
List<Offset> paceSeries(Workout w) {
  final moving = w.track.where((p) => p.moving).toList();
  if (moving.length < 2 || w.distance < 50) return [];
  final bin = w.distance < 1500 ? 50.0 : (w.distance < 8000 ? 100.0 : 250.0);
  final raw = <Offset>[];
  var start = moving.first;
  for (final p in moving.skip(1)) {
    final dd = p.distance - start.distance;
    if (dd >= bin) {
      final dt = p.movingSec - start.movingSec;
      if (dt > 0) raw.add(Offset(p.distance, dt / dd * 1000));
      start = p;
    }
  }
  // 3구간 이동평균
  return [
    for (var i = 0; i < raw.length; i++)
      Offset(
        raw[i].dx,
        [
              for (var j = math.max(0, i - 1);
                  j <= math.min(raw.length - 1, i + 1);
                  j++)
                raw[j].dy
            ].reduce((a, b) => a + b) /
            (math.min(raw.length - 1, i + 1) - math.max(0, i - 1) + 1),
      )
  ];
}

class _Legend extends StatelessWidget {
  final String value, unit, label;
  final Color color;
  const _Legend(this.value, this.unit, this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(value, style: numStyle(30).copyWith(color: color)),
          const SizedBox(width: 4),
          Text(unit,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w800, fontSize: 13)),
        ]),
      ),
      const SizedBox(height: 4),
      Text(label, style: labelStyle),
    ]);
  }
}

class _ChartPainter extends CustomPainter {
  final List<Offset> pace;
  final List<Offset> elev;
  final double totalDist;
  final double avgPace;

  _ChartPainter(
      {required this.pace,
      required this.elev,
      required this.totalDist,
      required this.avgPace});

  @override
  void paint(Canvas canvas, Size size) {
    if (totalDist <= 0) return;
    const bottomPad = 34.0;
    final h = size.height - bottomPad;
    double x(double d) => d / totalDist * size.width;

    // km 세로선 + 라벨
    final grid = Paint()
      ..color = line
      ..strokeWidth = 1;
    final stepKm = totalDist > 20000 ? 5 : (totalDist > 8000 ? 2 : 1);
    for (var k = stepKm; k * 1000 <= totalDist; k += stepKm) {
      final gx = x(k * 1000.0);
      canvas.drawLine(Offset(gx, 0), Offset(gx, h), grid);
      final tp = TextPainter(
        text: TextSpan(
            text: '$k.0',
            style: const TextStyle(color: ink, fontSize: 14)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(gx - tp.width / 2, h + 8));
    }

    // 고도: 아래 40% 영역 채움
    if (elev.length >= 2) {
      final minA = elev.map((e) => e.dy).reduce(math.min);
      final maxA = elev.map((e) => e.dy).reduce(math.max);
      final span = math.max(20.0, maxA - minA);
      final top = h * 0.55;
      double y(double a) => h - (a - minA) / span * (h - top);
      final path = Path()..moveTo(x(elev.first.dx), h);
      for (final e in elev) {
        path.lineTo(x(e.dx), y(e.dy));
      }
      path
        ..lineTo(x(elev.last.dx), h)
        ..close();
      canvas.drawPath(path, Paint()..color = const Color(0xFFDDF8E4));
      final hi = elev.reduce((a, b) => a.dy >= b.dy ? a : b);
      _dotLabel(canvas, Offset(x(hi.dx), y(hi.dy)), '${hi.dy.round()}m',
          elevGreen);
    }

    // 페이스: 위 55% 영역, 위로 갈수록 빠름(작은 값)
    if (pace.length >= 2) {
      final vals = pace.map((p) => p.dy).toList()..sort();
      // 극단값(신호등 정지 등) 잘라서 보기 좋게
      final lo = vals[(vals.length * 0.02).floor()];
      final hiV = vals[((vals.length - 1) * 0.98).floor()];
      final pad = math.max(20.0, (hiV - lo) * 0.2);
      final minP = lo - pad, maxP = hiV + pad;
      final area = h * 0.5;
      double y(double p) =>
          ((p.clamp(minP, maxP) - minP) / (maxP - minP)) * area + 10;
      final path = Path()..moveTo(x(pace.first.dx), y(pace.first.dy));
      for (final p in pace.skip(1)) {
        path.lineTo(x(p.dx), y(p.dy));
      }
      canvas.drawPath(
          path,
          Paint()
            ..color = paceBlue
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
            ..strokeJoin = StrokeJoin.round);

      // 평균 페이스 점선
      final ay = y(avgPace);
      final dash = Paint()
        ..color = paceBlue
        ..strokeWidth = 1.5;
      for (var dx = 0.0; dx < size.width; dx += 8) {
        canvas.drawLine(Offset(dx, ay), Offset(dx + 4, ay), dash);
      }
      final fastest = pace.reduce((a, b) => a.dy <= b.dy ? a : b);
      _dotLabel(canvas, Offset(x(fastest.dx), y(fastest.dy)),
          formatPace(fastest.dy), paceBlue);
    }
  }

  void _dotLabel(Canvas c, Offset p, String text, Color color) {
    c.drawCircle(p, 5, Paint()..color = color);
    final tp = TextPainter(
      text: TextSpan(
          text: text,
          style: TextStyle(
              color: color, fontSize: 15, fontWeight: FontWeight.w800)),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = math.max(0.0, p.dx - tp.width / 2);
    tp.paint(c, Offset(dx, p.dy - tp.height - 6));
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) => false;
}

// ── 1km 스플릿 ─────────────────────────────────────────
class _SplitsTab extends StatelessWidget {
  final Workout w;
  const _SplitsTab(this.w);

  @override
  Widget build(BuildContext context) {
    final splits = w.splits;
    if (splits.isEmpty) {
      return const Center(child: Text('1km 미만 기록입니다'));
    }
    final full = splits.where((s) => s.distance >= 1000).toList();
    final paces = full.map((s) => s.paceSecPerKm).toList();
    final minP = paces.isEmpty ? 0.0 : paces.reduce(math.min);
    final maxP = paces.isEmpty ? 0.0 : paces.reduce(math.max);
    // 느릴수록 긴 막대 (가장 빠른 = 25%, 가장 느린 = 100%)
    double frac(double p) =>
        maxP - minP < 1 ? 0.6 : 0.25 + 0.75 * (p - minP) / (maxP - minP);
    final avgFrac = full.isEmpty ? null : frac(w.avgPaceSecPerKm);

    return Column(children: [
      Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
        decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: line))),
        child: const Row(children: [
          SizedBox(
              width: 44,
              child: Text('KM',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
          Expanded(
              child: Text('페이스',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
          SizedBox(width: 62, child: Icon(Icons.trending_up)),
          SizedBox(width: 62, child: Icon(Icons.trending_down)),
        ]),
      ),
      Expanded(
        child: ListView.builder(
          itemCount: splits.length,
          itemBuilder: (_, i) {
            final s = splits[i];
            final isFull = s.distance >= 1000;
            final label = isFull
                ? '${s.index}.0'
                : ((splits.length - 1) + s.distance / 1000).toStringAsFixed(1);
            String? tag;
            if (isFull && full.length >= 2) {
              if (s.paceSecPerKm == maxP) tag = '🐢';
              if (s.paceSecPerKm == minP) tag = '🐇';
            }
            return SizedBox(
              height: 60,
              child: Row(children: [
                SizedBox(
                    width: 64,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 20),
                      child: Text(label,
                          style: const TextStyle(
                              fontSize: 15, letterSpacing: 1)),
                    )),
                Expanded(
                  child: LayoutBuilder(builder: (_, c) {
                    return Stack(alignment: Alignment.centerLeft, children: [
                      if (isFull)
                        Container(
                          width: c.maxWidth * frac(s.paceSecPerKm),
                          height: 56,
                          color: const Color(0xFFD5D8DC),
                        ),
                      if (avgFrac != null)
                        Positioned(
                          left: c.maxWidth * avgFrac,
                          top: 0,
                          bottom: 0,
                          child: CustomPaint(
                              size: const Size(1, 60),
                              painter: _DashPainter()),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: Text(
                          '${formatPace(s.paceSecPerKm)}${tag == null ? '' : '  $tag'}',
                          style: const TextStyle(
                              fontSize: 16,
                              letterSpacing: 2,
                              fontFeatures: [FontFeature.tabularFigures()]),
                        ),
                      ),
                    ]);
                  }),
                ),
                SizedBox(
                    width: 62,
                    child: Text('${s.gain.round()}m',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 15))),
                SizedBox(
                    width: 62,
                    child: Text('${s.loss.round()}m',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 15))),
              ]),
            );
          },
        ),
      ),
    ]);
  }
}

class _DashPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = ink
      ..strokeWidth = 1.5;
    for (var y = 0.0; y < size.height; y += 6) {
      canvas.drawLine(Offset(0, y), Offset(0, y + 3), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
