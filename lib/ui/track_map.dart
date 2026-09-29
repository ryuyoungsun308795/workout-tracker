import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gm;
import 'package:latlong2/latlong.dart' show LatLng;

import '../services/heading.dart';

/// 빌드 때 Google 지도 키가 들어갔는지(--dart-define=GOOGLE_MAPS=true)
const useGoogleMaps = bool.fromEnvironment('GOOGLE_MAPS');

/// 이동경로 지도
///
/// - Google 키가 있으면: Google 위성(지명 포함) / 일반 지도
/// - 없으면: Esri 위성 / OpenStreetMap
/// - 오른쪽 위 나침반: 누르면 북쪽이 위로, 한 번 더 누르면 폰이 향한 방향이 위로
class TrackMap extends StatelessWidget {
  final List<LatLng> route;
  final LatLng? current;
  final bool follow; // 기록 중: 현재 위치를 따라감
  final bool fitRoute; // 결과 화면: 경로 전체가 보이게
  final bool showStartEnd;

  const TrackMap({
    super.key,
    required this.route,
    this.current,
    this.follow = false,
    this.fitRoute = false,
    this.showStartEnd = false,
  });

  @override
  Widget build(BuildContext context) => useGoogleMaps
      ? _GoogleTrackMap(this)
      : _OsmTrackMap(this);
}

const _fallback = LatLng(37.2636, 127.0286); // 수원시청
const _routeYellow = Color(0xFFFFD400);
const _startGreen = Color(0xFF22C55E);
const _endRed = Color(0xFFEF2D56);

bool _satellite = true; // 앱 실행 중 선택 유지

enum _Orient { free, north, heading }

/// 지도 공통: 나침반 모드·사용자 조작·현재 위치 따라가기
mixin _MapLogic<T extends StatefulWidget> on State<T> {
  TrackMap get cfg;
  _Orient orient = _Orient.north;
  double bearing = 0; // 지도 위쪽이 가리키는 방위(도)
  bool userMoved = false;
  StreamSubscription<double>? _headingSub;
  double? _lastHeading;

  LatLng get center =>
      cfg.current ?? (cfg.route.isNotEmpty ? cfg.route.last : _fallback);

  /// 지도 구현이 카메라를 옮김
  void applyCamera({LatLng? target, double? bearing});

  void onCompassTap() {
    if (orient == _Orient.heading || bearing.abs() > 0.5) {
      _setOrient(_Orient.north);
      applyCamera(bearing: 0);
    } else {
      _setOrient(_Orient.heading);
      userMoved = false;
    }
    setState(() {});
  }

  void _setOrient(_Orient o) {
    orient = o;
    if (o == _Orient.heading) {
      _headingSub ??= HeadingSensor.instance.stream.listen((h) {
        if (_lastHeading != null && _angleDiff(h, _lastHeading!) < 2) return;
        _lastHeading = h;
        applyCamera(target: userMoved ? null : center, bearing: h);
      });
    } else {
      _headingSub?.cancel();
      _headingSub = null;
      _lastHeading = null;
    }
  }

  /// 사용자가 손가락으로 지도를 돌림
  void onUserRotated() {
    if (orient != _Orient.free) setState(() => _setOrient(_Orient.free));
  }

  void recenter() {
    setState(() => userMoved = false);
    applyCamera(target: center);
  }

  void followIfNeeded(TrackMap old) {
    if (userMoved) return;
    if (cfg.follow || (old.current == null && cfg.current != null)) {
      applyCamera(target: center);
    }
  }

  @override
  void dispose() {
    _headingSub?.cancel();
    super.dispose();
  }

  Widget overlayButtons() => Positioned(
        right: 10,
        top: 10,
        child: Column(children: [
          _Compass(
              bearing: bearing,
              headingMode: orient == _Orient.heading,
              onTap: onCompassTap),
          const SizedBox(height: 8),
          _mapButton(
            _satellite ? Icons.map_outlined : Icons.satellite_alt_outlined,
            () => setState(() => _satellite = !_satellite),
          ),
          if (userMoved && !cfg.fitRoute) ...[
            const SizedBox(height: 8),
            _mapButton(Icons.my_location, recenter),
          ],
        ]),
      );
}

double _angleDiff(double a, double b) {
  final d = (a - b).abs() % 360;
  return d > 180 ? 360 - d : d;
}

// ── Google 지도 ────────────────────────────────────────
class _GoogleTrackMap extends StatefulWidget {
  final TrackMap cfg;
  const _GoogleTrackMap(this.cfg);

  @override
  State<_GoogleTrackMap> createState() => _GoogleTrackMapState();
}

class _GoogleTrackMapState extends State<_GoogleTrackMap>
    with _MapLogic<_GoogleTrackMap> {
  @override
  TrackMap get cfg => widget.cfg;

  gm.GoogleMapController? _c;
  double _zoom = 16;
  LatLng? _target;
  bool _touching = false;
  double? _commandedBearing;

  static gm.LatLng _g(LatLng p) => gm.LatLng(p.latitude, p.longitude);

  @override
  void didUpdateWidget(covariant _GoogleTrackMap old) {
    super.didUpdateWidget(old);
    followIfNeeded(old.cfg);
  }

  @override
  void applyCamera({LatLng? target, double? bearing}) {
    final c = _c;
    if (c == null) return;
    final b = bearing ?? this.bearing;
    _commandedBearing = b;
    c.animateCamera(gm.CameraUpdate.newCameraPosition(gm.CameraPosition(
      target: _g(target ?? _target ?? center),
      zoom: _zoom,
      bearing: b,
    )));
  }

  Future<void> _fit() async {
    final r = cfg.route;
    if (!cfg.fitRoute || r.length < 2) return;
    var s = r.first.latitude, n = s, w = r.first.longitude, e = w;
    for (final p in r) {
      s = math.min(s, p.latitude);
      n = math.max(n, p.latitude);
      w = math.min(w, p.longitude);
      e = math.max(e, p.longitude);
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await _c?.moveCamera(gm.CameraUpdate.newLatLngBounds(
        gm.LatLngBounds(
            southwest: gm.LatLng(s, w), northeast: gm.LatLng(n, e)),
        48));
  }

  @override
  Widget build(BuildContext context) {
    final route = cfg.route.map(_g).toList();
    return Stack(children: [
      Listener(
        onPointerDown: (_) => _touching = true,
        onPointerUp: (_) => _touching = false,
        onPointerCancel: (_) => _touching = false,
        child: gm.GoogleMap(
          initialCameraPosition:
              gm.CameraPosition(target: _g(center), zoom: 16),
          mapType: _satellite ? gm.MapType.hybrid : gm.MapType.normal,
          compassEnabled: false,
          mapToolbarEnabled: false,
          zoomControlsEnabled: false,
          tiltGesturesEnabled: false,
          myLocationButtonEnabled: false,
          myLocationEnabled: cfg.current != null && !cfg.showStartEnd,
          onMapCreated: (c) {
            _c = c;
            _fit();
          },
          onCameraMove: (p) {
            _zoom = p.zoom;
            _target = LatLng(p.target.latitude, p.target.longitude);
            final rotatedByUser = _touching &&
                _angleDiff(p.bearing, _commandedBearing ?? bearing) > 3;
            if (p.bearing != bearing) setState(() => bearing = p.bearing);
            if (_touching && !cfg.fitRoute && !userMoved) {
              setState(() => userMoved = true);
            }
            if (rotatedByUser) onUserRotated();
          },
          polylines: {
            if (route.length >= 2) ...{
              gm.Polyline(
                polylineId: const gm.PolylineId('border'),
                points: route,
                color: _satellite ? Colors.black54 : Colors.white,
                width: 9,
                zIndex: 1,
              ),
              gm.Polyline(
                polylineId: const gm.PolylineId('route'),
                points: route,
                color: _satellite ? _routeYellow : Colors.black,
                width: 5,
                zIndex: 2,
              ),
            },
          },
          circles: {
            if (cfg.showStartEnd && route.isNotEmpty) ...{
              _dot('start', route.first, _startGreen),
              _dot('end', route.last, _endRed),
            },
          },
        ),
      ),
      overlayButtons(),
    ]);
  }

  gm.Circle _dot(String id, gm.LatLng p, Color c) => gm.Circle(
        circleId: gm.CircleId(id),
        center: p,
        radius: 8,
        fillColor: c,
        strokeColor: Colors.white,
        strokeWidth: 3,
        zIndex: 3,
      );
}

// ── 키 없을 때: Esri 위성 / OSM ───────────────────────
class _OsmTrackMap extends StatefulWidget {
  final TrackMap cfg;
  const _OsmTrackMap(this.cfg);

  @override
  State<_OsmTrackMap> createState() => _OsmTrackMapState();
}

class _OsmTrackMapState extends State<_OsmTrackMap>
    with _MapLogic<_OsmTrackMap> {
  @override
  TrackMap get cfg => widget.cfg;

  final _controller = MapController();
  bool _ready = false;

  @override
  void didUpdateWidget(covariant _OsmTrackMap old) {
    super.didUpdateWidget(old);
    followIfNeeded(old.cfg);
  }

  @override
  void applyCamera({LatLng? target, double? bearing}) {
    if (!_ready) return;
    final cam = _controller.camera;
    // flutter_map 회전은 방위의 반대 부호
    _controller.moveAndRotate(target ?? cam.center, cam.zoom,
        bearing == null ? cam.rotation : -bearing);
  }

  @override
  Widget build(BuildContext context) {
    final fit = cfg.fitRoute && cfg.route.length >= 2;
    final lineColor = _satellite ? _routeYellow : Colors.black;
    return Stack(children: [
      FlutterMap(
        mapController: _controller,
        options: MapOptions(
          initialCenter: center,
          initialZoom: 16,
          maxZoom: 19,
          initialCameraFit: fit
              ? CameraFit.coordinates(
                  coordinates: cfg.route,
                  padding: const EdgeInsets.all(40),
                  maxZoom: 18)
              : null,
          onMapReady: () => _ready = true,
          onPositionChanged: (cam, hasGesture) {
            final b = (-cam.rotation) % 360;
            if (_angleDiff(b, bearing) > 0.1) setState(() => bearing = b);
            if (hasGesture && !cfg.fitRoute && !userMoved) {
              setState(() => userMoved = true);
            }
          },
          onMapEvent: (e) {
            if (e is MapEventRotate && e.source != MapEventSource.mapController) {
              onUserRotated();
            }
          },
        ),
        children: [
          if (_satellite) ...[
            TileLayer(
              urlTemplate:
                  'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
              userAgentPackageName: 'com.ryuyoungsun.workout_tracker',
              maxNativeZoom: 19,
            ),
            TileLayer(
              urlTemplate:
                  'https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}',
              userAgentPackageName: 'com.ryuyoungsun.workout_tracker',
              maxNativeZoom: 19,
            ),
          ] else
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.ryuyoungsun.workout_tracker',
              maxNativeZoom: 19,
            ),
          if (cfg.route.length >= 2)
            PolylineLayer(polylines: [
              Polyline(
                points: cfg.route,
                strokeWidth: 5,
                color: lineColor,
                borderColor: _satellite ? Colors.black54 : Colors.white,
                borderStrokeWidth: 1.5,
              ),
            ]),
          MarkerLayer(rotate: true, markers: [
            if (cfg.showStartEnd && cfg.route.isNotEmpty) ...[
              _dot(cfg.route.first, _startGreen),
              _dot(cfg.route.last, _endRed),
            ],
            if (cfg.current != null && !cfg.showStartEnd)
              _dot(cfg.current!, const Color(0xFF2F80ED), size: 20),
          ]),
          RichAttributionWidget(
            alignment: AttributionAlignment.bottomLeft,
            attributions: [
              TextSourceAttribution(
                  _satellite ? 'Esri, Maxar, Earthstar' : 'OpenStreetMap'),
            ],
          ),
        ],
      ),
      overlayButtons(),
    ]);
  }

  Marker _dot(LatLng p, Color c, {double size = 18}) => Marker(
        point: p,
        width: size,
        height: size,
        child: Container(
          decoration: BoxDecoration(
            color: c,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black38)],
          ),
        ),
      );
}

// ── 공통 버튼 ─────────────────────────────────────────
Widget _mapButton(IconData icon, VoidCallback onTap) => Material(
      color: Colors.white,
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        child:
            SizedBox(width: 44, height: 44, child: Icon(icon, color: Colors.black)),
      ),
    );

/// N 나침반: 바늘이 항상 실제 북쪽을 가리킴
class _Compass extends StatelessWidget {
  final double bearing;
  final bool headingMode;
  final VoidCallback onTap;

  const _Compass(
      {required this.bearing, required this.headingMode, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 2,
      shape: CircleBorder(
          side: headingMode
              ? const BorderSide(color: Color(0xFF2F80ED), width: 3)
              : BorderSide.none),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Transform.rotate(
            angle: -bearing * math.pi / 180,
            child: CustomPaint(painter: _NeedlePainter()),
          ),
        ),
      ),
    );
  }
}

class _NeedlePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final north = Path()
      ..moveTo(c.dx, c.dy - 17)
      ..lineTo(c.dx - 6, c.dy)
      ..lineTo(c.dx + 6, c.dy)
      ..close();
    final south = Path()
      ..moveTo(c.dx, c.dy + 17)
      ..lineTo(c.dx - 6, c.dy)
      ..lineTo(c.dx + 6, c.dy)
      ..close();
    canvas.drawPath(north, Paint()..color = const Color(0xFFEF2D56));
    canvas.drawPath(south, Paint()..color = const Color(0xFFB0B0B0));
    final tp = TextPainter(
      text: const TextSpan(
          text: 'N',
          style: TextStyle(
              color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(c.dx - tp.width / 2, c.dy - 11));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
