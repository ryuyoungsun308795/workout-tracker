import 'package:flutter_test/flutter_test.dart';
import 'package:workout_tracker/services/heading.dart';

void main() {
  // 폰을 평평하게 들고(중력 = +z) 위쪽(y)이 향한 방향
  const g = [0.0, 0.0, 9.8];
  test('북쪽', () {
    // 지자기: 북쪽 + 아래(한국 복각)
    expect(HeadingSensor.azimuth(g, [0, 20, -40]), closeTo(0, 0.5));
  });
  test('동쪽 (북쪽이 폰 왼쪽)', () {
    expect(HeadingSensor.azimuth(g, [-20, 0, -40]), closeTo(90, 0.5));
  });
  test('남쪽', () {
    expect(HeadingSensor.azimuth(g, [0, -20, -40]), closeTo(180, 0.5));
  });
  test('서쪽', () {
    expect(HeadingSensor.azimuth(g, [20, 0, -40]), closeTo(270, 0.5));
  });
  test('세워 든 상태(중력 = +y), 뒷면이 북쪽', () {
    // 화면이 나를 보고 폰 뒤쪽(-z)이 북쪽
    expect(HeadingSensor.azimuth([0, 9.8, 0], [0, -40, -20]), closeTo(0, 1));
  });
}
