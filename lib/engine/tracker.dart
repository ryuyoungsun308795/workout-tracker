import 'dart:math' as math;

import 'calc.dart';
import 'models.dart';

/// 운동 기록 엔진 (플랫폼 독립 · 테스트 가능)
///
/// 자동 휴식 규칙:
/// - 마지막으로 확정된 점(anchor)에서 반경 [restRadius] 안에 머무는 점은 '보류'.
/// - 반경을 벗어나면 보류 점들을 확정하여 거리·시간·칼로리에 반영.
/// - anchor 이후 [restAfter] 동안 반경을 못 벗어나면 **anchor 시각부터** 휴식으로
///   전환하고 보류 거리는 버린다(제자리 GPS 흔들림이 거리로 쌓이지 않음).
/// - 휴식 중 반경을 벗어나면 자동으로 운동 재개.
class Tracker {
  final ActivityType type;
  final double weightKg;
  final DateTime startTime;
  final Duration restAfter;
  final double restRadius;
  final double maxAccuracy;

  /// 고도 오르내림으로 인정하는 최소 변화(m) — 잡음 제거
  double elevationThreshold;

  Tracker({
    required this.type,
    required this.weightKg,
    required this.startTime,
    this.restAfter = const Duration(seconds: 60),
    this.restRadius = 12,
    this.maxAccuracy = 25,
    this.elevationThreshold = 3,
  });

  // ── 결과 ─────────────────────────────────────────
  final List<TrackPoint> track = [];
  final List<RestInterval> rests = [];
  final List<Split> splits = [];
  double distance = 0;
  double kcal = 0;
  double gain = 0;
  double loss = 0;
  double? maxAlt;
  double? minAlt;
  double maxSpeed = 0;
  double currentSpeed = 0; // m/s
  double lastAccuracy = 999;

  // ── 내부 상태 ────────────────────────────────────
  GeoSample? _anchor; // 마지막 확정 점
  final List<GeoSample> _pending = [];
  GeoSample? _lastSample;
  double? _elevRef; // 히스테리시스 기준 고도
  double _splitStartMoving = 0;
  double _splitGain = 0;
  double _splitLoss = 0;
  final List<_Seg> _recent = []; // 최대속도 계산용 최근 확정 구간
  bool _paused = false;

  bool get isResting => rests.isNotEmpty && rests.last.end == null;
  bool get isPaused => _paused;
  bool get isAutoResting => isResting && !rests.last.manual;

  /// 표시용 거리(보류 거리 포함)
  double get liveDistance => distance + _pendingDistance();

  double restSeconds(DateTime now) =>
      rests.fold(0.0, (s, r) => s + r.secondsUntil(now));

  double movingSeconds(DateTime now) => math.max(
      0, now.difference(startTime).inMilliseconds / 1000 - restSeconds(now));

  double avgPaceSecPerKm(DateTime now) {
    final d = liveDistance;
    return d > 10 ? movingSeconds(now) / d * 1000 : 0;
  }

  double avgSpeedKmh(DateTime now) {
    final t = movingSeconds(now);
    return t > 0 ? liveDistance / t * 3.6 : 0;
  }

  /// 현재 진행 중인 구간(1km 미만)
  Split currentSplit(DateTime now) => Split(
        splits.length + 1,
        liveDistance - splits.length * 1000,
        movingSeconds(now) - _splitStartMoving,
        _splitGain,
        _splitLoss,
      );

  // ── 입력 ─────────────────────────────────────────

  /// 매초 호출: 위치가 안 들어와도 1분 정지를 감지
  void tick(DateTime now) {
    if (_paused || isResting) return;
    final a = _anchor;
    if (a != null && now.difference(a.time) >= restAfter) {
      _pending.clear();
      rests.add(RestInterval(a.time));
      currentSpeed = 0;
    }
  }

  void pause(DateTime now) {
    if (_paused) return;
    _paused = true;
    _pending.clear();
    currentSpeed = 0;
    if (isResting) {
      rests.last.end = now; // 자동휴식 → 수동정지로 넘김
    }
    rests.add(RestInterval(now, manual: true));
  }

  void resume(DateTime now) {
    if (!_paused) return;
    _paused = false;
    rests.last.end = now;
    _anchor = null; // 정지 중 이동한 거리는 세지 않음
  }

  void finish(DateTime now) {
    if (!_paused) tick(now);
    if (isResting) {
      rests.last.end = now;
    } else if (_pending.isNotEmpty) {
      _commit(List.of(_pending)); // 마지막 몇 m도 반영
    }
    _pending.clear();
    _paused = false;
  }

  void addSample(GeoSample s) {
    lastAccuracy = s.accuracy;
    if (s.accuracy > maxAccuracy) return;
    tick(s.time);
    _updateElevation(s.alt);

    final prev = _lastSample;
    _lastSample = s;

    if (_paused) {
      _pushTrack(s, moving: false);
      return;
    }

    final a = _anchor;
    if (a == null) {
      _anchor = s;
      _pushTrack(s, moving: true);
      return;
    }

    // 튀는 점 제거
    final jump = haversine(
        _tail().lat, _tail().lng, s.lat, s.lng);
    final dt = s.time.difference(_tail().time).inMilliseconds / 1000;
    if (dt > 0 && jump / dt > _maxPlausibleSpeed && dt < 30) return;

    final fromAnchor = haversine(a.lat, a.lng, s.lat, s.lng);
    final radius = restRadius + math.min(s.accuracy, 10) * 0.5;

    if (isResting) {
      if (fromAnchor > radius) {
        // 휴식 끝: 휴식 중 관측된 마지막 점 시각 기준으로 재개
        final end = (prev != null && prev.time.isAfter(rests.last.start))
            ? prev.time
            : s.time;
        rests.last.end = end.isAfter(s.time) ? s.time : end;
        _commit([s]);
      } else {
        _pushTrack(s, moving: false);
      }
      return;
    }

    if (fromAnchor > radius) {
      _pending.add(s);
      _commit(List.of(_pending));
      _pending.clear();
    } else {
      _pending.add(s);
      currentSpeed = s.speed >= 0 ? s.speed : 0;
    }
  }

  // ── 내부 ─────────────────────────────────────────

  double get _maxPlausibleSpeed => type == ActivityType.running ? 12 : 8;

  GeoSample _tail() => _pending.isNotEmpty ? _pending.last : _anchor!;

  double _pendingDistance() {
    var d = 0.0;
    var p = _anchor;
    if (p == null) return 0;
    for (final s in _pending) {
      d += haversine(p!.lat, p.lng, s.lat, s.lng);
      p = s;
    }
    return d;
  }

  void _commit(List<GeoSample> samples) {
    var p = _anchor!;
    for (final s in samples) {
      final d = haversine(p.lat, p.lng, s.lat, s.lng);
      final dt = s.time.difference(p.time).inMilliseconds / 1000;
      final movingDt = _movingBetween(p.time, s.time);
      final grade = (p.alt != null && s.alt != null && d > 1)
          ? (s.alt! - p.alt!) / d
          : 0.0;
      kcal += segmentKcal(
          type: type,
          weightKg: weightKg,
          meters: d,
          seconds: movingDt,
          grade: grade);

      // 1km 스플릿 경계 통과 → 보간
      final before = distance;
      distance += d;
      while (distance >= (splits.length + 1) * 1000) {
        final boundary = (splits.length + 1) * 1000.0;
        final frac = d > 0 ? (boundary - before) / d : 1.0;
        final tCross = p.time.add(Duration(
            milliseconds: (dt * 1000 * frac.clamp(0.0, 1.0)).round()));
        final mCross = movingSeconds(tCross);
        splits.add(Split(splits.length + 1, 1000, mCross - _splitStartMoving,
            _splitGain, _splitLoss));
        _splitStartMoving = mCross;
        _splitGain = 0;
        _splitLoss = 0;
      }

      if (movingDt > 0) {
        _recent.add(_Seg(d, movingDt));
        _updateMaxSpeed();
        currentSpeed = s.speed >= 0 ? s.speed : d / movingDt;
      }
      _pushTrack(s, moving: true);
      p = s;
    }
    _anchor = p;
  }

  /// 최근 10초 이상 구간 평균으로 최대속도 (순간 튐 방지)
  void _updateMaxSpeed() {
    var d = 0.0, t = 0.0;
    for (var i = _recent.length - 1; i >= 0; i--) {
      d += _recent[i].d;
      t += _recent[i].t;
      if (t >= 10) {
        _recent.removeRange(0, i);
        break;
      }
    }
    if (t >= 10) maxSpeed = math.max(maxSpeed, d / t);
  }

  double _movingBetween(DateTime a, DateTime b) =>
      math.max(0, movingSeconds(b) - movingSeconds(a));

  void _updateElevation(double? alt) {
    if (alt == null) return;
    maxAlt = maxAlt == null ? alt : math.max(maxAlt!, alt);
    minAlt = minAlt == null ? alt : math.min(minAlt!, alt);
    final ref = _elevRef;
    if (ref == null) {
      _elevRef = alt;
      return;
    }
    final diff = alt - ref;
    if (diff >= elevationThreshold) {
      gain += diff;
      _splitGain += diff;
      _elevRef = alt;
    } else if (diff <= -elevationThreshold) {
      loss += -diff;
      _splitLoss += -diff;
      _elevRef = alt;
    }
  }

  void _pushTrack(GeoSample s, {required bool moving}) {
    track.add(TrackPoint(s.lat, s.lng, s.alt, s.time, distance,
        movingSeconds(s.time), moving));
  }

  /// 운동 종료 후 결과 정리
  Workout toWorkout({required DateTime end, required Profile profile}) {
    final all = [...splits];
    final last = currentSplit(end);
    if (last.distance >= 10) all.add(last);
    return Workout(
      id: startTime.millisecondsSinceEpoch.toString(),
      type: type,
      start: startTime,
      end: end,
      distance: distance,
      movingSec: movingSeconds(end),
      restSec: restSeconds(end),
      kcal: kcal,
      gain: gain,
      loss: loss,
      maxAlt: maxAlt,
      minAlt: minAlt,
      maxSpeed: maxSpeed,
      splits: all,
      track: List.of(track),
      rests: List.of(rests),
      profile: profile,
    );
  }
}

class _Seg {
  final double d;
  final double t;
  _Seg(this.d, this.t);
}
