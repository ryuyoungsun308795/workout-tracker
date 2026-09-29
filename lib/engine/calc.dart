import 'dart:math' as math;

import 'models.dart';

/// 두 좌표 사이 거리(m) — 하버사인
double haversine(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  final dLat = _rad(lat2 - lat1);
  final dLng = _rad(lng2 - lng1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_rad(lat1)) *
          math.cos(_rad(lat2)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  return 2 * r * math.asin(math.min(1, math.sqrt(a)));
}

double _rad(double d) => d * math.pi / 180;

/// 구간 소모 칼로리(kcal) — ACSM 대사 공식
///
/// 걷기: VO2 = 3.5 + 0.1·v + 1.8·v·경사
/// 달리기: VO2 = 3.5 + 0.2·v + 0.9·v·경사   (v = m/분, VO2 = ml/kg/분)
/// 산소 1L ≈ 5 kcal. 내리막은 경사 0으로 계산(에너지가 줄지 않음).
/// 등산은 험한 지형·배낭을 고려해 1.15배.
double segmentKcal({
  required ActivityType type,
  required double weightKg,
  required double meters,
  required double seconds,
  required double grade,
}) {
  if (seconds <= 0 || weightKg <= 0) return 0;
  final vMin = meters / seconds * 60; // m/분
  final g = grade.clamp(0.0, 0.45);
  // 8km/h(134m/분) 이상이면 달리기 공식
  final running = vMin >= 134;
  final vo2 = running
      ? 3.5 + 0.2 * vMin + 0.9 * vMin * g
      : 3.5 + 0.1 * vMin + 1.8 * vMin * g;
  final factor = type == ActivityType.hiking ? 1.15 : 1.0;
  return vo2 * weightKg / 1000 * 5 * (seconds / 60) * factor;
}

/// 기압(hPa) → 고도(m), 국제표준대기
double pressureToAltitude(double hPa) =>
    44330.0 * (1 - math.pow(hPa / 1013.25, 1 / 5.255));

String formatDuration(double seconds, {bool alwaysHours = false}) {
  final s = seconds.round();
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  if (h > 0 || alwaysHours) return '${two(h)}:${two(m)}:${two(sec)}';
  return '${two(m)}:${two(sec)}';
}

/// 페이스(초/km) → "08:19"
String formatPace(double secPerKm) {
  if (secPerKm <= 0 || secPerKm.isInfinite || secPerKm > 5999) return '--:--';
  final s = secPerKm.round();
  return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
}
