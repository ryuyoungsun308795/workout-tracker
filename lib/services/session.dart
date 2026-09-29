import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart' hide ActivityType;
import 'package:permission_handler/permission_handler.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../engine/elevation.dart';
import '../engine/models.dart';
import '../engine/tracker.dart';
import 'storage.dart';

/// 앱 전체에서 하나: GPS·기압계를 받아 Tracker에 넣고 화면에 알림
class Session extends ChangeNotifier {
  Session._();
  static final Session instance = Session._();

  Profile profile = const Profile();
  bool profileSaved = false;
  ActivityType type = ActivityType.running;

  Tracker? tracker;
  bool get active => tracker != null;

  Position? lastPosition; // 대기 화면 지도·GPS 신호용
  String? error;

  StreamSubscription<Position>? _posSub;
  StreamSubscription<BarometerEvent>? _baroSub;
  Timer? _ticker;
  Timer? _flusher;
  ElevationFilter? _elev;

  Future<void> init() async {
    final p = await Storage.loadProfile();
    if (p != null) {
      profile = p;
      profileSaved = true;
    }
    notifyListeners();
  }

  Future<void> saveProfile(Profile p) async {
    profile = p;
    profileSaved = true;
    await Storage.saveProfile(p);
    notifyListeners();
  }

  void setType(ActivityType t) {
    if (active) return;
    type = t;
    notifyListeners();
  }

  /// 위치 권한·GPS 켜짐 확인. 문제 있으면 사용자에게 보여줄 문구를 반환.
  Future<String?> ensurePermissions() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      await Geolocator.openLocationSettings();
      return '휴대폰의 위치(GPS)를 켜주세요.';
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied) {
      return '위치 권한이 필요합니다.';
    }
    if (perm == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
      return '설정 > 권한에서 위치를 「앱 사용 중 허용」으로 바꿔주세요.';
    }
    // 화면 꺼짐 중 기록 유지용 알림 표시 권한(안드로이드 13+)
    await Permission.notification.request();
    return null;
  }

  /// 배터리 최적화 제외 요청(삼성 등에서 화면 꺼지면 기록이 끊기는 것 방지)
  Future<void> requestBatteryExemption() async {
    if (await Permission.ignoreBatteryOptimizations.isDenied) {
      await Permission.ignoreBatteryOptimizations.request();
    }
  }

  /// 대기 화면: 현재 위치만 가볍게 추적
  Future<void> startPreview() async {
    if (active || _posSub != null) return;
    final perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return;
    }
    _posSub = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.high,
        intervalDuration: const Duration(seconds: 3),
      ),
    ).listen((p) {
      lastPosition = p;
      notifyListeners();
    }, onError: (_) {});
  }

  Future<void> stopPreview() async {
    if (active) return;
    await _posSub?.cancel();
    _posSub = null;
  }

  Future<void> start() async {
    if (active) return;
    await _posSub?.cancel();
    _posSub = null;

    final now = DateTime.now();
    final tr = Tracker(type: type, weightKg: profile.weightKg, startTime: now);
    tracker = tr;
    _elev = ElevationFilter();
    await Storage.liveBegin({
      'e': 'h',
      'type': type.name,
      't': now.millisecondsSinceEpoch,
      'profile': profile.toJson(),
    });

    _baroSub = barometerEventStream(samplingPeriod: SensorInterval.uiInterval)
        .listen((e) => _elev?.onPressure(e.pressure), onError: (_) {});

    _posSub = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 1),
        useMSLAltitude: true,
        foregroundNotificationConfig: ForegroundNotificationConfig(
          notificationTitle: '${type.label} 기록 중',
          notificationText: '화면이 꺼져도 경로를 기록하고 있습니다.',
          notificationChannelName: '운동 기록',
          enableWakeLock: true,
          setOngoing: true,
        ),
      ),
    ).listen(_onPosition, onError: (e) {
      error = 'GPS 오류: $e';
      notifyListeners();
    });

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      tracker?.tick(DateTime.now());
      notifyListeners();
    });
    _flusher = Timer.periodic(
        const Duration(seconds: 10), (_) => Storage.liveFlush());
    notifyListeners();
  }

  void _onPosition(Position p) {
    lastPosition = p;
    final tr = tracker;
    if (tr == null) return;
    final alt = _elev!.update(p.altitude, p.altitudeAccuracy);
    final s = GeoSample(
      lat: p.latitude,
      lng: p.longitude,
      alt: alt,
      time: p.timestamp.toLocal(),
      accuracy: p.accuracy,
      speed: p.speed,
    );
    tr.addSample(s);
    Storage.liveAppend({'e': 's', ...s.toJson()});
    notifyListeners();
  }

  void pause() {
    final now = DateTime.now();
    tracker?.pause(now);
    Storage.liveAppend({'e': 'p', 't': now.millisecondsSinceEpoch});
    notifyListeners();
  }

  void resume() {
    final now = DateTime.now();
    tracker?.resume(now);
    Storage.liveAppend({'e': 'r', 't': now.millisecondsSinceEpoch});
    notifyListeners();
  }

  /// 운동 종료 → 결과 저장 후 반환. 거리가 거의 없으면 [discard]로 버릴 수 있음.
  Future<Workout?> stop({bool discard = false}) async {
    final tr = tracker;
    if (tr == null) return null;
    await _cleanup();
    final end = DateTime.now();
    tr.finish(end);
    tracker = null;
    await Storage.liveEnd();
    Workout? w;
    if (!discard) {
      w = tr.toWorkout(end: end, profile: profile);
      await Storage.saveWorkout(w);
    }
    notifyListeners();
    return w;
  }

  Future<void> _cleanup() async {
    _ticker?.cancel();
    _flusher?.cancel();
    _ticker = null;
    _flusher = null;
    await _posSub?.cancel();
    await _baroSub?.cancel();
    _posSub = null;
    _baroSub = null;
  }

  /// 앱이 기록 도중 종료됐을 때 남은 백업으로 결과 복원
  static Workout? replay(List<Map<String, dynamic>> log) {
    final h = log.first;
    if (h['e'] != 'h') return null;
    final profile = Profile.fromJson(h['profile'] as Map<String, dynamic>);
    final start = DateTime.fromMillisecondsSinceEpoch(h['t'] as int);
    final tr = Tracker(
      type: ActivityType.values.byName(h['type'] as String),
      weightKg: profile.weightKg,
      startTime: start,
    );
    var last = start;
    for (final e in log.skip(1)) {
      final t = DateTime.fromMillisecondsSinceEpoch(e['t'] as int);
      switch (e['e']) {
        case 's':
          tr.addSample(GeoSample.fromJson(e));
        case 'p':
          tr.pause(t);
        case 'r':
          tr.resume(t);
      }
      if (t.isAfter(last)) last = t;
    }
    tr.finish(last);
    return tr.toWorkout(end: last, profile: profile);
  }
}
