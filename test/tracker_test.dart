import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/engine/calc.dart';
import 'package:workout_tracker/engine/models.dart';
import 'package:workout_tracker/engine/tracker.dart';

// 위도 1도 ≈ 111,195m → 북쪽으로 m 만큼 이동한 위도
double north(double m) => 37.28 + m / 111195.0;

void main() {
  final t0 = DateTime(2026, 9, 29, 20, 0, 0);

  GeoSample at(double meters, int sec, {double? alt, double acc = 5}) =>
      GeoSample(
          lat: north(meters),
          lng: 127.0,
          alt: alt,
          time: t0.add(Duration(seconds: sec)),
          accuracy: acc);

  Tracker make({ActivityType type = ActivityType.running}) =>
      Tracker(type: type, weightKg: 70, startTime: t0);

  test('등속 달리기: 거리·페이스·스플릿', () {
    final tr = make();
    // 3 m/s(= 5:33/km)로 2.5km
    for (var s = 0; s <= 833; s++) {
      tr.addSample(at(s * 3.0, s));
      tr.tick(t0.add(Duration(seconds: s)));
    }
    final end = t0.add(const Duration(seconds: 833));
    tr.finish(end);
    expect(tr.distance, closeTo(2499, 3));
    expect(tr.splits.length, 2);
    expect(tr.splits[0].seconds, closeTo(333.3, 2));
    expect(tr.splits[1].seconds, closeTo(333.3, 2));
    expect(tr.rests, isEmpty);
    expect(tr.avgPaceSecPerKm(end), closeTo(333.3, 2));
    expect(tr.maxSpeed, closeTo(3.0, 0.05));
    final w = tr.toWorkout(end: end, profile: const Profile());
    expect(w.splits.length, 3); // 마지막 0.5km 포함
    expect(w.splits.last.distance, closeTo(499, 3));
  });

  test('1분 정지 → 멈춘 시점부터 자동 휴식, 이동하면 자동 재개', () {
    final tr = make();
    var sec = 0;
    // 0~300초: 2 m/s 이동 (600m)
    for (; sec <= 300; sec++) {
      tr.addSample(at(sec * 2.0, sec));
    }
    // 301~500초: 제자리 (GPS가 ±3m 흔들림)
    for (; sec <= 500; sec++) {
      tr.addSample(at(600 + (sec.isEven ? 3 : -3), sec));
      tr.tick(t0.add(Duration(seconds: sec)));
    }
    expect(tr.isAutoResting, isTrue);
    // 휴식 시작은 멈춘 시점(≈300초) — 1분 뒤(360초)가 아님
    final restStart = tr.rests.first.start.difference(t0).inSeconds;
    expect(restStart, inInclusiveRange(290, 301));
    // 흔들림은 거리에 안 쌓임
    expect(tr.distance, closeTo(600, 15));

    // 501~700초: 다시 2 m/s 이동
    for (; sec <= 700; sec++) {
      tr.addSample(at(600 + (sec - 500) * 2.0, sec));
    }
    expect(tr.isResting, isFalse);
    final end = t0.add(Duration(seconds: 700));
    tr.finish(end);
    expect(tr.distance, closeTo(1000, 20));
    expect(tr.restSeconds(end), closeTo(200, 15));
    expect(tr.movingSeconds(end), closeTo(500, 15));
  });

  test('GPS가 끊겨도 1분 지나면 휴식 전환(tick)', () {
    final tr = make();
    for (var s = 0; s <= 100; s++) {
      tr.addSample(at(s * 2.0, s));
    }
    tr.tick(t0.add(const Duration(seconds: 150)));
    expect(tr.isResting, isFalse);
    tr.tick(t0.add(const Duration(seconds: 161)));
    expect(tr.isResting, isTrue);
  });

  test('수동 일시정지 중 이동거리는 세지 않음', () {
    final tr = make();
    for (var s = 0; s <= 100; s++) {
      tr.addSample(at(s * 2.0, s));
    }
    tr.pause(t0.add(const Duration(seconds: 100)));
    for (var s = 101; s <= 200; s++) {
      tr.addSample(at(200 + (s - 100) * 2.0, s));
    }
    tr.resume(t0.add(const Duration(seconds: 200)));
    for (var s = 201; s <= 300; s++) {
      tr.addSample(at(400 + (s - 200) * 2.0, s));
    }
    final end = t0.add(const Duration(seconds: 300));
    tr.finish(end);
    expect(tr.distance, closeTo(400, 15));
    expect(tr.movingSeconds(end), closeTo(200, 2));
  });

  test('부정확한 점·튀는 점은 무시', () {
    final tr = make();
    for (var s = 0; s <= 60; s++) {
      tr.addSample(at(s * 2.0, s));
    }
    tr.addSample(at(5000, 61)); // 순간이동
    tr.addSample(at(9999, 62, acc: 80)); // 정확도 80m
    for (var s = 63; s <= 120; s++) {
      tr.addSample(at(s * 2.0, s));
    }
    tr.finish(t0.add(const Duration(seconds: 120)));
    expect(tr.distance, closeTo(240, 15));
  });

  test('고도: 상승/하강 누적과 잡음 제거', () {
    final tr = make(type: ActivityType.hiking);
    // 오르막 100m 올라갔다 50m 내려옴 + ±1m 잡음
    var sec = 0;
    for (var i = 0; i <= 100; i++, sec += 5) {
      tr.addSample(at(i * 5.0, sec, alt: 100 + i + (i.isEven ? 1 : -1)));
    }
    for (var i = 1; i <= 50; i++, sec += 5) {
      tr.addSample(at(500 + i * 5.0, sec, alt: 200 - i + (i.isEven ? 1 : -1)));
    }
    expect(tr.gain, closeTo(100, 6));
    expect(tr.loss, closeTo(50, 6));
    expect(tr.maxAlt, closeTo(201, 1));
  });

  test('칼로리: 70kg 10km/h 1시간 달리기 ≈ 700~800kcal', () {
    final k = segmentKcal(
        type: ActivityType.running,
        weightKg: 70,
        meters: 10000,
        seconds: 3600,
        grade: 0);
    expect(k, inInclusiveRange(700, 800));
    // 오르막 등산은 평지 걷기보다 많이
    final flat = segmentKcal(
        type: ActivityType.hiking,
        weightKg: 70,
        meters: 3000,
        seconds: 3600,
        grade: 0);
    final up = segmentKcal(
        type: ActivityType.hiking,
        weightKg: 70,
        meters: 3000,
        seconds: 3600,
        grade: 0.15);
    expect(up, greaterThan(flat * 2));
  });

  test('신체지수', () {
    const p = Profile(heightCm: 175, weightKg: 75, waistCm: 88, male: true);
    expect(p.bmi, closeTo(24.5, 0.1));
    expect(p.waistToHeight, closeTo(0.503, 0.001));
    expect(p.bodyFatPercent, closeTo(24.2, 0.2));
  });

  test('Workout JSON 왕복', () {
    final tr = make();
    for (var s = 0; s <= 400; s++) {
      tr.addSample(at(s * 3.0, s, alt: 50));
    }
    final end = t0.add(const Duration(seconds: 400));
    tr.finish(end);
    final w = tr.toWorkout(end: end, profile: const Profile());
    final w2 = Workout.fromJson(w.toJson());
    expect(w2.distance, w.distance);
    expect(w2.splits.length, w.splits.length);
    expect(w2.track.length, w.track.length);
    expect(w2.type, ActivityType.running);
  });

  test('표시 형식', () {
    expect(formatPace(499), '08:19');
    expect(formatDuration(2591), '43:11');
    expect(formatDuration(2591, alwaysHours: true), '00:43:11');
  });
}
