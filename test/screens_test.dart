import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:workout_tracker/engine/models.dart';
import 'package:workout_tracker/engine/tracker.dart';
import 'package:workout_tracker/ui/profile_screen.dart';
import 'package:workout_tracker/ui/result_screen.dart';

/// 5.2km 호수 한 바퀴 비슷한 가짜 기록(중간에 2분 휴식, 언덕 포함)
Workout fakeWorkout() {
  final t0 = DateTime(2026, 9, 27, 20, 1);
  final tr = Tracker(type: ActivityType.running, weightKg: 72, startTime: t0);
  var d = 0.0;
  for (var s = 0; s <= 2700; s++) {
    final resting = s > 1200 && s < 1320;
    if (!resting) d += 1.9 + (s % 300) / 300; // 페이스 변화
    final alt = 70 + 15 * ((d % 2000) / 2000 - 0.5).abs() * 2;
    tr.addSample(GeoSample(
        lat: 37.29 + d / 111195.0,
        lng: 127.04,
        alt: alt,
        time: t0.add(Duration(seconds: s))));
  }
  final end = t0.add(const Duration(seconds: 2700));
  tr.finish(end);
  return tr.toWorkout(
      end: end,
      profile: const Profile(heightCm: 172, weightKg: 72, waistCm: 86));
}

void main() {
  setUpAll(() => initializeDateFormatting('ko'));

  test('가짜 기록 정상 생성', () {
    final w = fakeWorkout();
    expect(w.distance, greaterThan(5000));
    expect(w.splits.length, greaterThanOrEqualTo(5));
    expect(w.rests.length, 1);
    expect(w.restSec, closeTo(120, 70));
  });

  testWidgets('결과 화면: 그래프·스플릿 탭 렌더링', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: ResultScreen(workout: fakeWorkout())));
    await tester.pump();
    // 지도 타일은 테스트 환경에서 네트워크가 없어 실패할 수 있으므로 무시
    tester.takeException();
    expect(find.text('평균 페이스'), findsWidgets);

    await tester.tap(find.byIcon(Icons.show_chart));
    await tester.pumpAndSettle();
    expect(find.textContaining('전체:'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.bar_chart));
    await tester.pumpAndSettle();
    expect(find.text('1.0'), findsOneWidget);
    expect(find.textContaining('🐇'), findsOneWidget);
    expect(find.textContaining('🐢'), findsOneWidget);
  });

  testWidgets('신체 정보 화면: BMI 표시', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ProfileScreen(first: true)));
    await tester.pump();
    expect(find.text('BMI'), findsOneWidget);
    expect(find.textContaining('24.2'), findsOneWidget); // 기본 170cm·70kg
  });
}
