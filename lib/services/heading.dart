import 'dart:async';
import 'dart:math' as math;

import 'package:sensors_plus/sensors_plus.dart';

/// 폰이 향한 방향(0=북, 90=동) — 가속도계+지자기 센서로 계산
///
/// 안드로이드 SensorManager.getRotationMatrix/getOrientation 과 같은 식.
/// 구독자가 있을 때만 센서를 켠다.
class HeadingSensor {
  HeadingSensor._();
  static final HeadingSensor instance = HeadingSensor._();

  late final _out =
      StreamController<double>.broadcast(onListen: _start, onCancel: _stop);

  Stream<double> get stream => _out.stream;

  StreamSubscription<AccelerometerEvent>? _accSub;
  StreamSubscription<MagnetometerEvent>? _magSub;
  List<double>? _g;
  List<double>? _m;
  double? _sin, _cos; // 방위각 평활(0/360 경계 문제 없게 sin·cos로)

  void _start() {
    _accSub = accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval)
        .listen((e) {
      _g = _lowPass([e.x, e.y, e.z], _g, 0.15);
      _emit();
    }, onError: (_) {});
    _magSub = magnetometerEventStream(samplingPeriod: SensorInterval.uiInterval)
        .listen((e) {
      _m = _lowPass([e.x, e.y, e.z], _m, 0.15);
    }, onError: (_) {});
  }

  void _stop() {
    _accSub?.cancel();
    _magSub?.cancel();
    _accSub = null;
    _magSub = null;
  }

  static List<double> _lowPass(List<double> v, List<double>? prev, double a) =>
      prev == null ? v : [for (var i = 0; i < 3; i++) prev[i] + a * (v[i] - prev[i])];

  void _emit() {
    final az = azimuth(_g, _m);
    if (az == null) return;
    final r = az * math.pi / 180;
    _sin = _sin == null ? math.sin(r) : _sin! * 0.8 + math.sin(r) * 0.2;
    _cos = _cos == null ? math.cos(r) : _cos! * 0.8 + math.cos(r) * 0.2;
    final deg = math.atan2(_sin!, _cos!) * 180 / math.pi;
    _out.add((deg + 360) % 360);
  }

  /// 중력 g, 지자기 m 벡터(폰 좌표계) → 방위각(도). 계산 불가면 null.
  static double? azimuth(List<double>? g, List<double>? m) {
    if (g == null || m == null) return null;
    // H = m × g (동쪽)
    var hx = m[1] * g[2] - m[2] * g[1];
    var hy = m[2] * g[0] - m[0] * g[2];
    var hz = m[0] * g[1] - m[1] * g[0];
    final normH = math.sqrt(hx * hx + hy * hy + hz * hz);
    if (normH < 0.1) return null; // 자유낙하·자기장 없음
    hx /= normH;
    hy /= normH;
    hz /= normH;
    final normG = math.sqrt(g[0] * g[0] + g[1] * g[1] + g[2] * g[2]);
    final ax = g[0] / normG, az = g[2] / normG;
    // M = g × H (북쪽)
    final my = az * hx - ax * hz;
    final deg = math.atan2(hy, my) * 180 / math.pi;
    return (deg + 360) % 360;
  }
}
