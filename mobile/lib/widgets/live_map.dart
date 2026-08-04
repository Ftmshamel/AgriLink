import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../services/geo.dart';
import '../utils/app_colors.dart';

/// A pin drawn on [LiveRouteMap], built from real order data.
class MapStop {
  const MapStop({
    required this.point,
    required this.label,
    required this.icon,
    required this.color,
  });

  final LatLng point;
  final String label;
  final IconData icon;
  final Color color;
}

/// The route map used by rider navigation and buyer tracking.
///
/// Everything it draws comes from [stops] and [riderPoint]; it holds no
/// sample coordinates of its own. When [followMe] is set it also streams the
/// device GPS and reports each fix through [onPosition] so the caller can
/// publish it to Firestore.
class LiveRouteMap extends StatefulWidget {
  const LiveRouteMap({
    super.key,
    required this.stops,
    this.riderPoint,
    this.followMe = false,
    this.showControls = true,
    this.focusPoint,
    this.height = 270,
    this.onPosition,
    this.onRouteResolved,
  });

  final List<MapStop> stops;

  /// Last known rider position from Firestore, drawn for buyers watching a
  /// delivery. Ignored while [followMe] is streaming a live device fix.
  final LatLng? riderPoint;
  final bool followMe;
  final bool showControls;
  final LatLng? focusPoint;
  final double height;
  final void Function(Position position)? onPosition;
  final void Function(RoutePath route)? onRouteResolved;

  @override
  State<LiveRouteMap> createState() => _LiveRouteMapState();
}

class _LiveRouteMapState extends State<LiveRouteMap> {
  final _mapController = MapController();
  StreamSubscription<Position>? _positionSubscription;

  RoutePath? _route;
  LatLng? _deviceLocation;
  double _heading = 0;
  double _accuracy = 0;
  bool _following = false;
  bool _loadingRoute = false;
  bool _requestingLocation = false;
  bool _mapReady = false;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _following = widget.followMe;
    _resolveRoute();
    if (widget.followMe) _startTracking();
  }

  @override
  void didUpdateWidget(covariant LiveRouteMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameStops(oldWidget.stops, widget.stops)) _resolveRoute();
    if (widget.focusPoint != null &&
        widget.focusPoint != oldWidget.focusPoint &&
        !_following) {
      _moveWhenReady(widget.focusPoint!, 15);
    }
    if (widget.followMe && !oldWidget.followMe) _startTracking();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }

  bool _sameStops(List<MapStop> a, List<MapStop> b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index].point != b[index].point) return false;
    }
    return true;
  }

  List<LatLng> get _waypoints => [
        if (_deviceLocation != null && widget.followMe) _deviceLocation!,
        ...widget.stops.map((stop) => stop.point),
      ];

  Future<void> _resolveRoute() async {
    final waypoints = _waypoints;
    if (waypoints.length < 2) {
      setState(() => _route = null);
      return;
    }
    setState(() => _loadingRoute = true);
    final resolved = await RouteService.route(waypoints);
    if (!mounted) return;
    setState(() {
      _route = resolved;
      _loadingRoute = false;
      _notice = resolved.isEstimate
          ? 'Live routing unavailable — showing a direct line.'
          : null;
    });
    widget.onRouteResolved?.call(resolved);
    if (!_following) _fitRoute();
  }

  void _moveWhenReady(LatLng point, double zoom) {
    if (!_mapReady) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _mapReady) _mapController.move(point, zoom);
    });
  }

  void _fitRoute() {
    final points = <LatLng>[
      ...?_route?.points,
      ...widget.stops.map((stop) => stop.point),
      if (_deviceLocation != null) _deviceLocation!,
      if (widget.riderPoint != null) widget.riderPoint!,
    ];
    if (points.length < 2 || !_mapReady) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_mapReady) return;
      _mapController.fitCamera(
        CameraFit.coordinates(
          coordinates: points,
          padding: const EdgeInsets.fromLTRB(42, 54, 42, 50),
          maxZoom: 15,
        ),
      );
    });
  }

  Future<void> _startTracking() async {
    if (_requestingLocation) return;
    setState(() => _requestingLocation = true);
    try {
      await GeoService.ensurePermission();
      await _positionSubscription?.cancel();
      _positionSubscription = GeoService.watch().listen((position) {
        if (!mounted) return;
        final current = LatLng(position.latitude, position.longitude);
        setState(() {
          _deviceLocation = current;
          _heading = position.heading.isFinite ? position.heading : 0;
          _accuracy = position.accuracy;
          _notice = null;
        });
        widget.onPosition?.call(position);
        if (_following && _mapReady) _mapController.move(current, 16.5);
      }, onError: (_) {});

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 25),
        ),
      );
      if (!mounted) return;
      final current = LatLng(position.latitude, position.longitude);
      setState(() {
        _deviceLocation = current;
        _heading = position.heading.isFinite ? position.heading : 0;
        _accuracy = position.accuracy;
      });
      widget.onPosition?.call(position);
      if (_mapReady) _mapController.move(current, _following ? 16.5 : 13);
      await _resolveRoute();
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _notice = '$error'.replaceFirst('Exception: ', ''),
      );
    } finally {
      if (mounted) setState(() => _requestingLocation = false);
    }
  }

  LatLng get _initialCenter {
    if (widget.focusPoint != null) return widget.focusPoint!;
    if (widget.riderPoint != null) return widget.riderPoint!;
    if (widget.stops.isNotEmpty) return widget.stops.first.point;
    // Central Luzon, the platform's operating region.
    return const LatLng(15.48, 120.96);
  }

  @override
  Widget build(BuildContext context) {
    final riderMarker = _deviceLocation ?? widget.riderPoint;
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: const Color(0xFFEAF1E8),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFDCE6D9)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _initialCenter,
              initialZoom: widget.stops.length > 1 ? 11.5 : 14,
              onMapReady: () {
                _mapReady = true;
                if (!_following) _fitRoute();
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'ph.agrilink.mobile',
                maxZoom: 19,
              ),
              if ((_route?.points.length ?? 0) > 1)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _route!.points,
                      strokeWidth: 6,
                      color: green,
                      borderStrokeWidth: 2,
                      borderColor: Colors.white,
                    ),
                  ],
                ),
              if (_deviceLocation != null && _accuracy > 0)
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: _deviceLocation!,
                      radius: _accuracy.clamp(18, 55).toDouble(),
                      color: const Color(0x223A9618),
                      borderColor: const Color(0x663A9618),
                      borderStrokeWidth: 1.5,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  for (final stop in widget.stops)
                    Marker(
                      point: stop.point,
                      width: 120,
                      height: 64,
                      child: NamedMapPin(
                        label: stop.label,
                        icon: stop.icon,
                        color: stop.color,
                      ),
                    ),
                  if (riderMarker != null)
                    Marker(
                      point: riderMarker,
                      width: 58,
                      height: 58,
                      child: Transform.rotate(
                        angle: _heading * math.pi / 180,
                        child: const RiderNavigationMarker(),
                      ),
                    ),
                ],
              ),
            ],
          ),
          if (_loadingRoute)
            const Positioned(
              top: 12,
              left: 0,
              right: 0,
              child: Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 8),
                        Text('Calculating route…'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (widget.showControls)
            Positioned(
              right: 12,
              bottom: 40,
              child: Column(
                children: [
                  MapControlButton(
                    icon: Icons.add,
                    onTap: () => _mapController.move(
                      _mapController.camera.center,
                      _mapController.camera.zoom + 1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  MapControlButton(
                    icon: Icons.remove,
                    onTap: () => _mapController.move(
                      _mapController.camera.center,
                      _mapController.camera.zoom - 1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  MapControlButton(icon: Icons.route, onTap: _fitRoute),
                  const SizedBox(height: 6),
                  MapControlButton(
                    icon: _following ? Icons.gps_fixed : Icons.gps_not_fixed,
                    loading: _requestingLocation,
                    active: _following,
                    onTap: () {
                      setState(() => _following = !_following);
                      if (_following) {
                        if (_deviceLocation != null) {
                          _mapController.move(_deviceLocation!, 16.5);
                        } else {
                          _startTracking();
                        }
                      } else {
                        _fitRoute();
                      }
                    },
                  ),
                ],
              ),
            ),
          if (_notice != null)
            Positioned(
              left: 10,
              right: 10,
              top: 10,
              child: Material(
                color: const Color(0xEEFFFFFF),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.all(9),
                  child: Text(
                    _notice!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            left: 12,
            bottom: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _route != null && !_route!.isEstimate
                    ? '${_route!.distanceLabel} • ${_route!.etaLabel} • OSM'
                    : '© OpenStreetMap contributors',
                style: const TextStyle(fontSize: 10, color: muted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class NamedMapPin extends StatelessWidget {
  const NamedMapPin({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
  });
  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          constraints: const BoxConstraints(maxWidth: 116),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(7),
            boxShadow: const [
              BoxShadow(color: Color(0x33000000), blurRadius: 5),
            ],
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900),
          ),
        ),
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
          ),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
      ],
    );
  }
}

class RiderNavigationMarker extends StatelessWidget {
  const RiderNavigationMarker({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: Color(0x44000000), blurRadius: 10)],
      ),
      padding: const EdgeInsets.all(5),
      child: Container(
        decoration: BoxDecoration(
          color: darkGreen,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
        ),
        child: const Icon(
          Icons.navigation_rounded,
          color: Colors.white,
          size: 30,
        ),
      ),
    );
  }
}

class MapControlButton extends StatelessWidget {
  const MapControlButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.loading = false,
    this.active = false,
  });
  final IconData icon;
  final VoidCallback onTap;
  final bool loading;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? green : Colors.white,
      elevation: 2,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: loading ? null : onTap,
        borderRadius: BorderRadius.circular(9),
        child: SizedBox(
          width: 38,
          height: 38,
          child: loading
              ? const Padding(
                  padding: EdgeInsets.all(10),
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(icon, color: active ? Colors.white : green, size: 20),
        ),
      ),
    );
  }
}
