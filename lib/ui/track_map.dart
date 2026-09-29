import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// 위성지도(기본) / 일반지도 + 이동경로
///
/// 위성: Esri World Imagery(무료, API 키 불필요) + 지명 라벨 겹침
/// 일반: OpenStreetMap
class TrackMap extends StatefulWidget {
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
  State<TrackMap> createState() => _TrackMapState();
}

class _TrackMapState extends State<TrackMap> {
  static bool _satellite = true; // 앱 실행 중 선택 유지
  final _controller = MapController();
  bool _ready = false;
  bool _userMoved = false;

  static const _fallback = LatLng(37.2636, 127.0286); // 수원시청

  LatLng get _center =>
      widget.current ??
      (widget.route.isNotEmpty ? widget.route.last : _fallback);

  @override
  void didUpdateWidget(covariant TrackMap old) {
    super.didUpdateWidget(old);
    if (!_ready || _userMoved) return;
    if (widget.follow || (old.current == null && widget.current != null)) {
      _controller.move(_center, _controller.camera.zoom);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fit = widget.fitRoute && widget.route.length >= 2;
    final lineColor = _satellite ? const Color(0xFFFFD400) : Colors.black;
    return Stack(children: [
      FlutterMap(
        mapController: _controller,
        options: MapOptions(
          initialCenter: _center,
          initialZoom: 16,
          maxZoom: 19,
          initialCameraFit: fit
              ? CameraFit.coordinates(
                  coordinates: widget.route,
                  padding: const EdgeInsets.all(40),
                  maxZoom: 18)
              : null,
          interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
          onMapReady: () => _ready = true,
          onPositionChanged: (_, hasGesture) {
            if (hasGesture) setState(() => _userMoved = true);
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
          if (widget.route.length >= 2)
            PolylineLayer(polylines: [
              Polyline(
                points: widget.route,
                strokeWidth: 5,
                color: lineColor,
                borderColor: _satellite ? Colors.black54 : Colors.white,
                borderStrokeWidth: 1.5,
              ),
            ]),
          MarkerLayer(markers: [
            if (widget.showStartEnd && widget.route.isNotEmpty) ...[
              _dot(widget.route.first, const Color(0xFF22C55E)),
              _dot(widget.route.last, const Color(0xFFEF2D56)),
            ],
            if (widget.current != null && !widget.showStartEnd)
              _dot(widget.current!, const Color(0xFF2F80ED), size: 20),
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
      Positioned(
        right: 10,
        top: 10,
        child: Column(children: [
          _mapButton(
            _satellite ? Icons.map_outlined : Icons.satellite_alt_outlined,
            () => setState(() => _satellite = !_satellite),
          ),
          if (_userMoved && !widget.fitRoute) ...[
            const SizedBox(height: 8),
            _mapButton(Icons.my_location, () {
              setState(() => _userMoved = false);
              _controller.move(_center, _controller.camera.zoom);
            }),
          ],
        ]),
      ),
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

  Widget _mapButton(IconData icon, VoidCallback onTap) => Material(
        color: Colors.white,
        elevation: 2,
        shape: const RoundedRectangleBorder(),
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
              width: 42, height: 42, child: Icon(icon, color: Colors.black)),
        ),
      );
}
