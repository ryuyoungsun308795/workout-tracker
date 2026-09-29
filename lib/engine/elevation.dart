import 'calc.dart';

/// GPS 고도(오차 큼)와 기압계(상대 변화 정확)를 합쳐 고도를 만든다.
///
/// - 기압계가 있으면: 고도 = 기압고도 + 보정값. 보정값은 GPS 고도와의 차이를
///   처음엔 빠르게, 이후엔 아주 천천히 따라가서(날씨로 인한 기압 변화 흡수)
///   오르내림은 기압계가, 절대 높이는 GPS가 결정한다.
/// - 기압계가 없으면: GPS 고도를 지수평활.
class ElevationFilter {
  double? _baroAlt; // 최신 기압고도
  double? _offset;
  int _calibCount = 0;
  double? _gpsSmoothed;

  bool get hasBarometer => _baroAlt != null;

  void onPressure(double hPa) {
    if (hPa <= 0) return;
    final a = pressureToAltitude(hPa);
    // 기압 센서 잡음 완화
    _baroAlt = _baroAlt == null ? a : _baroAlt! * 0.8 + a * 0.2;
  }

  /// GPS 고도로 최종 고도를 계산. 둘 다 없으면 null.
  double? update(double? gpsAlt, double verticalAccuracy) {
    final gpsOk = gpsAlt != null && gpsAlt != 0 && verticalAccuracy < 30;
    if (_baroAlt != null) {
      if (gpsOk) {
        final diff = gpsAlt - _baroAlt!;
        if (_offset == null) {
          _offset = diff;
        } else {
          _calibCount++;
          final alpha = _calibCount < 20 ? 0.2 : 0.005;
          _offset = _offset! + (diff - _offset!) * alpha;
        }
      }
      if (_offset == null) return null;
      return _baroAlt! + _offset!;
    }
    if (!gpsOk) return _gpsSmoothed;
    _gpsSmoothed =
        _gpsSmoothed == null ? gpsAlt : _gpsSmoothed! * 0.8 + gpsAlt * 0.2;
    return _gpsSmoothed;
  }
}
