import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app.dart';
import '../models/agri_models.dart';
import '../services/delivery_proof.dart';
import '../services/geo.dart';
import '../services/notifications.dart';
import '../services/session.dart';
import '../utils/app_colors.dart';
import '../widgets/live_data.dart';
import '../widgets/live_map.dart';
import '../widgets/notification_bell.dart';
import '../widgets/ui_kit.dart';
import '../widgets/weather_card.dart';
import 'shared_screens.dart';

/// How riders can sort the open job pool.
enum PoolSort {
  nearMe('Near me'),
  bestPay('Best pay'),
  shortest('Shortest');

  const PoolSort(this.label);
  final String label;
}

/// Everything the rider tabs read, loaded once per refresh.
class RiderSnapshot {
  const RiderSnapshot({
    required this.pool,
    required this.mine,
    required this.trips,
    required this.riderPoint,
  });

  /// Packed orders nobody has accepted yet.
  final List<AgriOrder> pool;

  /// Orders already assigned to this rider.
  final List<AgriOrder> mine;
  final List<Map<String, dynamic>> trips;
  final LatLng? riderPoint;

  List<AgriOrder> get active =>
      mine.where((order) => order.status.isOpen).toList();
  List<AgriOrder> get delivered =>
      mine.where((order) => order.status == OrderStatus.delivered).toList();

  /// The trip the rider is currently running, if any.
  String? get activeTripId {
    for (final order in active) {
      if (order.tripId.isNotEmpty) return order.tripId;
    }
    return null;
  }

  List<AgriOrder> ordersForTrip(String tripId) =>
      mine.where((order) => order.tripId == tripId).toList();

  int get todayEarnings {
    final now = DateTime.now();
    return delivered.where((order) {
      final at = order.timeline[OrderStatus.delivered.wire];
      if (at == null) return false;
      final local = at.toLocal();
      return local.year == now.year &&
          local.month == now.month &&
          local.day == now.day;
    }).fold<int>(0, (total, order) => total + order.riderPayout);
  }

  int get todayTrips {
    final now = DateTime.now();
    return delivered
        .where((order) {
          final at = order.timeline[OrderStatus.delivered.wire];
          if (at == null) return false;
          final local = at.toLocal();
          return local.year == now.year &&
              local.month == now.month &&
              local.day == now.day;
        })
        .map((order) => order.tripId.isEmpty ? order.id : order.tripId)
        .toSet()
        .length;
  }

  int get lifetimeEarnings =>
      delivered.fold<int>(0, (total, order) => total + order.riderPayout);

  /// Groups the open pool into batches by destination town, which is what
  /// makes one trip able to serve several buyers.
  List<PooledBatch> batches(PoolSort sort) {
    final grouped = <String, List<AgriOrder>>{};
    for (final order in pool) {
      grouped.putIfAbsent(order.dropArea, () => []).add(order);
    }
    final batches = grouped.entries.map((entry) {
      final stops = _batchStops(entry.value);
      return PooledBatch(
        area: entry.key,
        orders: entry.value,
        distanceKm: _straightLineLength(stops),
        stops: stops,
      );
    }).toList();
    switch (sort) {
      case PoolSort.nearMe:
        batches.sort((a, b) =>
            _distanceToFirstPickup(a).compareTo(_distanceToFirstPickup(b)));
      case PoolSort.bestPay:
        batches.sort((a, b) => b.payout.compareTo(a.payout));
      case PoolSort.shortest:
        batches.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    }
    return batches;
  }

  double _distanceToFirstPickup(PooledBatch batch) {
    if (riderPoint == null) return batch.distanceKm;
    var nearest = double.infinity;
    for (final order in batch.orders) {
      final pickup = order.pickupPoint;
      if (pickup == null) continue;
      final distance = GeoService.distanceKm(riderPoint!, pickup);
      if (distance < nearest) nearest = distance;
    }
    return nearest.isFinite ? nearest : batch.distanceKm;
  }

  /// The trip in visiting order: every farm to collect from, then every buyer
  /// to drop at.
  ///
  /// The rider's own position is deliberately left out so the pool card and the
  /// Pooled route screen quote the same distance for the same trip. How far the
  /// rider is from the first farm is a separate question, answered by
  /// [_distanceToFirstPickup] for the "Near me" sort.
  List<LatLng> _batchStops(List<AgriOrder> orders) {
    final stops = <LatLng>[];
    for (final order in orders) {
      final pickup = order.pickupPoint;
      if (pickup != null && !stops.contains(pickup)) stops.add(pickup);
    }
    for (final order in orders) {
      final drop = order.dropPoint;
      if (drop != null) stops.add(drop);
    }
    return stops;
  }

  double _straightLineLength(List<LatLng> stops) {
    var total = 0.0;
    for (var index = 0; index < stops.length - 1; index++) {
      total += GeoService.distanceKm(stops[index], stops[index + 1]);
    }
    return total;
  }

  static Future<RiderSnapshot> load(String riderId) async {
    final results = await Future.wait([
      authService.database.listAgriOrders(),
      authService.database.listTrips(riderId: riderId),
      GeoService.tryCurrentPoint(),
      // Batch payouts are priced from these, so load them with the pool.
      authService.database.loadDeliveryRates(),
    ]);
    final all = results[0] as List<AgriOrder>;
    return RiderSnapshot(
      pool: all
          .where((order) =>
              order.status == OrderStatus.readyForPickup &&
              !order.hasRider &&
              order.isDueForPickup(DeliveryHours.manilaNow()))
          .toList(),
      mine: all.where((order) => order.riderId == riderId).toList(),
      trips: results[1] as List<Map<String, dynamic>>,
      riderPoint: results[2] as LatLng?,
    );
  }
}

/// Builds the ordered stop list for a trip: every farm first, then every buyer.
List<TripStop> buildTripStops(List<AgriOrder> orders, LatLng? riderPoint) {
  final pickups = <String, List<AgriOrder>>{};
  final drops = <String, List<AgriOrder>>{};
  for (final order in orders) {
    pickups.putIfAbsent(order.farmerId, () => []).add(order);
    drops.putIfAbsent('${order.buyerId}|${order.deliveryAddress}', () => [])
        .add(order);
  }

  List<TripStop> build(Map<String, List<AgriOrder>> groups, StopKind kind) {
    final stops = groups.values.map((group) {
      final first = group.first;
      return TripStop(
        kind: kind,
        title: kind == StopKind.pickup ? first.farmerName : first.buyerName,
        contactName: kind == StopKind.pickup ? first.farmerName : first.buyerName,
        phone: kind == StopKind.pickup ? first.farmerPhone : first.buyerPhone,
        address:
            kind == StopKind.pickup ? first.farmLocation : first.deliveryAddress,
        point: kind == StopKind.pickup ? first.pickupPoint : first.dropPoint,
        orders: group,
      );
    }).toList();
    if (riderPoint != null) {
      stops.sort((a, b) {
        if (a.point == null) return 1;
        if (b.point == null) return -1;
        return GeoService.distanceKm(riderPoint, a.point!)
            .compareTo(GeoService.distanceKm(riderPoint, b.point!));
      });
    }
    return stops;
  }

  return [
    ...build(pickups, StopKind.pickup),
    ...build(drops, StopKind.dropoff),
  ];
}

/// Full-screen map for driving to [stop] without leaving the app.
///
/// It streams GPS and passes each fix to [onPosition], the same as the trip
/// page, so buyers keep seeing the rider move while this is open.
class RiderNavigationPage extends StatefulWidget {
  const RiderNavigationPage({
    super.key,
    required this.stops,
    required this.stop,
    required this.onPosition,
  });

  final List<MapStop> stops;
  final TripStop stop;
  final void Function(Position position) onPosition;

  @override
  State<RiderNavigationPage> createState() => _RiderNavigationPageState();
}

class _RiderNavigationPageState extends State<RiderNavigationPage> {
  RouteProgress? _progress;

  Future<void> _call() async {
    final phone = widget.stop.phone;
    if (phone.isEmpty || !await launchUrl(Uri(scheme: 'tel', path: phone))) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No contact number on file.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final stop = widget.stop;
    final leg = _progress?.toNextStop;
    return Scaffold(
      appBar: AppBar(
        title: Text(stop.isPickup ? 'To the farm' : 'To the buyer'),
      ),
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => LiveRouteMap(
                stops: widget.stops,
                followMe: true,
                headingUp: true,
                rounded: false,
                height: constraints.maxHeight,
                onPosition: widget.onPosition,
                onProgress: (progress) =>
                    setState(() => _progress = progress),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 12, 12),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: stop.isPickup ? orange : green,
                    foregroundColor: Colors.white,
                    child: Icon(
                      stop.isPickup ? Icons.agriculture : Icons.store,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          leg == null
                              ? 'Finding the road…'
                              : '${leg.distanceLabel} • ${leg.etaLabel}',
                          style: const TextStyle(
                            color: green,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          stop.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          stop.address.isEmpty
                              ? 'No address on file'
                              : stop.address,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Call contact',
                    onPressed: _call,
                    icon: const Icon(Icons.call),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens the phone's navigation app, falling back to OpenStreetMap.
Future<void> openNavigation(LatLng destination, {LatLng? from}) async {
  final google = Uri.parse(
    'https://www.google.com/maps/dir/?api=1'
    '&destination=${destination.latitude},${destination.longitude}'
    '&travelmode=driving',
  );
  if (await launchUrl(google, mode: LaunchMode.externalApplication)) return;

  // OSM wants "origin;destination"; with no GPS fix it still routes from the
  // leading semicolon, so the destination must always be included.
  final origin = from == null ? '' : '${from.latitude},${from.longitude}';
  final osm = Uri.parse(
    'https://www.openstreetmap.org/directions'
    '?engine=fossgis_osrm_car'
    '&route=${Uri.encodeComponent('$origin;'
        '${destination.latitude},${destination.longitude}')}',
  );
  await launchUrl(osm, mode: LaunchMode.externalApplication);
}

class RiderShell extends StatefulWidget {
  const RiderShell({super.key, required this.session});
  final AppSession session;

  @override
  State<RiderShell> createState() => _RiderShellState();
}

class _RiderShellState extends State<RiderShell> {
  int _index = 0;
  bool _online = true;

  @override
  void initState() {
    super.initState();
    _restoreAvailability();
  }

  /// Riders expect the app to remember whether they left themselves online.
  Future<void> _restoreAvailability() async {
    final account =
        await authService.database.getAccount(widget.session.user.id);
    if (!mounted || account == null) return;
    final stored = account['riderOnline'];
    if (stored is bool) setState(() => _online = stored);
    if (widget.session.user.payoutNumber.isEmpty) {
      setState(() => _online = false);
    }
  }

  Future<void> _setOnline(bool value) async {
    // A rider with nowhere to be paid would be delivering for free.
    if (value && widget.session.user.payoutNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Add your GCash or Maya payout number before going online.',
          ),
          persist: false,
          action: SnackBarAction(
            label: 'ADD',
            onPressed: () => openProfileEditor(context, widget.session),
          ),
        ),
      );
      return;
    }
    // Going offline only stops new trip offers. A rider part-way through a
    // trip still has farms and buyers waiting on them, who can still see and
    // call them, so the trip has to be finished first.
    if (!value) {
      final active = await _activeTripOrders();
      if (!mounted) return;
      if (active.isNotEmpty) {
        final buyers = {for (final order in active) order.buyerId}.length;
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Finish your trip first'),
            content: Text(
              'You still have ${plural(active.length, 'order')} for '
              '${plural(buyers, 'buyer')} on your current trip. The farm and '
              'buyers can still see and call you until every stop is done. '
              'Finish the trip, then go offline. If something is wrong, use '
              'Report a problem on the trip screen.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }
    }
    setState(() => _online = value);
    try {
      final point = value ? await GeoService.tryCurrentPoint() : null;
      await authService.database.setRiderAvailability(
        riderId: widget.session.user.id,
        online: value,
        latitude: point?.latitude,
        longitude: point?.longitude,
      );
      widget.session.bump();
    } catch (_) {
      // Availability is a convenience flag; a failed write should not block
      // the rider from using the app.
    }
  }

  /// Orders this rider has accepted and not yet delivered.
  Future<List<AgriOrder>> _activeTripOrders() async {
    try {
      final orders = await authService.database
          .listAgriOrders(riderId: widget.session.user.id);
      return orders.where((order) => order.status.isWithRider).toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      RiderDashboard(
        session: widget.session,
        online: _online,
        onToggle: _setOnline,
        onOpenPool: () => setState(() => _index = 1),
      ),
      RiderPool(
        session: widget.session,
        online: _online,
        onGoOnline: () => _setOnline(true),
      ),
      RiderTrips(session: widget.session),
      RiderProfile(session: widget.session),
    ];
    return Scaffold(
      body: SafeArea(child: LiveIndexedStack(index: _index, children: pages)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'Pool',
          ),
          NavigationDestination(
            icon: Icon(Icons.route_outlined),
            selectedIcon: Icon(Icons.route),
            label: 'Trips',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class RiderDashboard extends StatelessWidget {
  const RiderDashboard({
    super.key,
    required this.session,
    required this.online,
    required this.onToggle,
    required this.onOpenPool,
  });

  final AppSession session;
  final bool online;
  final ValueChanged<bool> onToggle;
  final VoidCallback onOpenPool;

  @override
  Widget build(BuildContext context) {
    return LiveBuilder<RiderSnapshot>(
      session: session,
      load: () => RiderSnapshot.load(session.user.id),
      builder: (context, data) {
        final snapshot = data.value;
        final active = snapshot?.active ?? const <AgriOrder>[];
        final tripId = snapshot?.activeTripId;
        final batches = online && snapshot != null
            ? snapshot.batches(PoolSort.nearMe)
            : const <PooledBatch>[];
        return LiveRefreshView(
          loading: data.loading,
          onRefresh: data.reload,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            children: [
              Row(
                children: [
                  const CircleAvatar(
                    backgroundColor: Color(0xFFFFE7C2),
                    child: Icon(Icons.person, color: orange),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Ready to ride?',
                          style: TextStyle(color: muted),
                        ),
                        Text(
                          session.user.name,
                          style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w700, fontFamily: headingFont, fontFamilyFallback: headingFallback,
                          ),
                        ),
                      ],
                    ),
                  ),
                  NotificationBell(
                    session: session,
                    load: () async {
                      final snapshot = await RiderSnapshot.load(
                        session.user.id,
                      );
                      return NoticeFeed.forRider(snapshot.mine, snapshot.pool);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: online ? darkGreen : const Color(0xFF475467),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .13),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        online ? Icons.wifi_tethering : Icons.wifi_off,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            online ? 'You’re online' : 'You’re offline',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.w700, fontFamily: headingFont, fontFamilyFallback: headingFallback,
                            ),
                          ),
                          Text(
                            online
                                ? tripId != null
                                    ? 'Finish your current trip to take '
                                        'another'
                                    : batches.isEmpty
                                    ? 'Waiting for packed farm orders'
                                    : '${batches.length} pooled route${batches.length == 1 ? '' : 's'} available now'
                                : 'Go online to receive trips',
                            style: const TextStyle(color: Color(0xFFD7E5D1)),
                          ),
                        ],
                      ),
                    ),
                    Switch(value: online, onChanged: onToggle),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: StatCard(
                      icon: Icons.payments_outlined,
                      label: 'Today',
                      value: formatPeso(snapshot?.todayEarnings ?? 0),
                      tint: lightGreen,
                      color: green,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatCard(
                      icon: Icons.local_shipping_outlined,
                      label: 'Trips',
                      value: '${snapshot?.todayTrips ?? 0}',
                      tint: const Color(0xFFFFF1DD),
                      color: orange,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 26),
              const SectionTitle(title: 'Delivery conditions', action: ''),
              const SizedBox(height: 12),
              WeatherPanel(
                session: session,
                audience: WeatherAudience.rider,
              ),
              const SizedBox(height: 26),
              const SectionTitle(title: 'Active delivery', action: ''),
              const SizedBox(height: 12),
              if (data.error != null && snapshot == null)
                LiveErrorCard(message: data.errorMessage, onRetry: data.reload)
              else if (active.isEmpty)
                const EmptyState(
                  icon: Icons.route_outlined,
                  title: 'No active trip',
                  message:
                      'Accept a pooled route from the Pool tab to start earning.',
                )
              else
                ActiveTripCard(
                  orders: active,
                  riderPoint: snapshot?.riderPoint,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ActiveTripPage(
                        session: session,
                        tripId: tripId ?? '',
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 26),
              SectionTitle(
                title: 'Nearby opportunities',
                action: 'Order pool',
                onAction: onOpenPool,
              ),
              const SizedBox(height: 12),
              if (!online)
                const EmptyState(
                  icon: Icons.wifi_off,
                  title: 'You’re offline',
                  message: 'Switch yourself online to see pooled routes.',
                )
              else if (batches.isEmpty)
                const EmptyState(
                  icon: Icons.inbox_outlined,
                  title: 'No routes right now',
                  message:
                      'Packed farm orders appear here the moment they are ready.',
                )
              else
                for (final batch in batches.take(3)) ...[
                  MiniOpportunity(
                    area: batch.route,
                    orders:
                        '${batch.orderCount} order${batch.orderCount == 1 ? '' : 's'} • ${batch.farmCount} farm${batch.farmCount == 1 ? '' : 's'}',
                    distance: formatKm(batch.distanceKm),
                    pay: formatPeso(batch.payout),
                    onTap: () => _openBatch(context, batch, snapshot),
                  ),
                  const SizedBox(height: 10),
                ],
            ],
          ),
        );
      },
    );
  }

  void _openBatch(
    BuildContext context,
    PooledBatch batch,
    RiderSnapshot? snapshot,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PoolDetailsPage(
          session: session,
          batch: batch,
          riderPoint: snapshot?.riderPoint,
        ),
      ),
    );
  }
}

/// The dashboard's active-trip summary, driven by the rider's real stops.
class ActiveTripCard extends StatelessWidget {
  const ActiveTripCard({
    super.key,
    required this.orders,
    required this.onTap,
    this.riderPoint,
  });

  final List<AgriOrder> orders;
  final VoidCallback onTap;
  final LatLng? riderPoint;

  @override
  Widget build(BuildContext context) {
    final stops = buildTripStops(orders, riderPoint);
    final done = stops.where((stop) => stop.isComplete).length;
    final pickups = stops.where((stop) => stop.isPickup).toList();
    final drops = stops.where((stop) => !stop.isPickup).toList();
    final pickupsDone = pickups.where((stop) => stop.isComplete).length;
    final payout =
        orders.fold<int>(0, (total, order) => total + order.riderPayout);
    final next = stops.firstWhere(
      (stop) => !stop.isComplete,
      orElse: () => stops.last,
    );
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              Row(
                children: [
                  Pill(
                    icon: Icons.route,
                    text: 'BATCH • ${orders.length} ORDER'
                        '${orders.length == 1 ? '' : 'S'}',
                    color: orange,
                  ),
                  const Spacer(),
                  Text(
                    formatPeso(payout),
                    style: const TextStyle(
                      fontSize: 20,
                      color: green,
                      fontWeight: FontWeight.w700, fontFamily: headingFont, fontFamilyFallback: headingFallback,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              RouteRow(
                color: orange,
                title:
                    'Pickup ${(pickupsDone + 1).clamp(1, pickups.length)} of ${pickups.length}',
                subtitle: next.isPickup
                    ? '${next.title}${next.point != null && riderPoint != null ? ' • ${formatKm(GeoService.exactKm(riderPoint!, next.point!))}' : ''}'
                    : 'All pickups complete',
              ),
              const RouteLine(),
              RouteRow(
                color: green,
                title:
                    '${drops.length} drop-off${drops.length == 1 ? '' : 's'}',
                subtitle: drops.isEmpty ? '—' : drops.first.address,
              ),
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: stops.isEmpty ? 0 : done / stops.length,
                minHeight: 7,
                borderRadius: const BorderRadius.all(Radius.circular(10)),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    '$done of ${stops.length} stops complete',
                    style: const TextStyle(color: muted, fontSize: 12),
                  ),
                  const Spacer(),
                  const Text(
                    'View route',
                    style: TextStyle(
                      color: green,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RiderPool extends StatefulWidget {
  const RiderPool({
    super.key,
    required this.session,
    required this.online,
    required this.onGoOnline,
  });

  final AppSession session;
  final bool online;
  final VoidCallback onGoOnline;

  @override
  State<RiderPool> createState() => _RiderPoolState();
}

class _RiderPoolState extends State<RiderPool> {
  PoolSort _sort = PoolSort.nearMe;
  bool _resolvingRoutes = false;

  /// Replaces the straight-line estimate on each card with the real driving
  /// distance and ETA.
  ///
  /// Routes are fetched one at a time and only for the batches on screen:
  /// this runs against the public OSRM demo server, and the pool reloads every
  /// few seconds, so hammering it with a burst per poll would be abusive.
  /// [RouteService] caches by waypoint list, making repeat polls free.
  Future<void> _resolveRoutes(List<PooledBatch> batches) async {
    if (_resolvingRoutes) return;
    final pending = batches
        .where((batch) =>
            batch.stops.length >= 2 && RouteService.cached(batch.stops) == null)
        .take(6)
        .toList();
    if (pending.isEmpty) return;
    _resolvingRoutes = true;
    try {
      for (final batch in pending) {
        await RouteService.route(batch.stops);
        if (!mounted) return;
      }
      if (mounted) setState(() {});
    } finally {
      _resolvingRoutes = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LiveBuilder<RiderSnapshot>(
      session: widget.session,
      load: () => RiderSnapshot.load(widget.session.user.id),
      builder: (context, data) {
        final snapshot = data.value;
        final batches =
            snapshot == null ? const <PooledBatch>[] : snapshot.batches(_sort);
        if (widget.online && batches.isNotEmpty) {
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _resolveRoutes(batches));
        }
        return LiveRefreshView(
          loading: data.loading,
          onRefresh: data.reload,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
            children: [
              const PageHeader(
                eyebrow: 'SMART POOLING',
                title: 'Open Order Pool',
                subtitle: 'Group deliveries heading in the same direction.',
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  for (final sort in PoolSort.values) ...[
                    Expanded(
                      child: FilterPill(
                        label: sort.label,
                        selected: _sort == sort,
                        onTap: () => setState(() => _sort = sort),
                      ),
                    ),
                    if (sort != PoolSort.values.last) const SizedBox(width: 8),
                  ],
                ],
              ),
              const SizedBox(height: 20),
              if (!widget.online)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 34,
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.wifi_off, size: 46, color: muted),
                        const SizedBox(height: 14),
                        const Text(
                          'You’re offline',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700, fontFamily: headingFont, fontFamilyFallback: headingFallback,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Go online to see and accept pooled farm deliveries.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: muted, height: 1.45),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: widget.onGoOnline,
                          icon: const Icon(Icons.wifi_tethering),
                          label: const Text('Go online'),
                        ),
                      ],
                    ),
                  ),
                )
              else if (data.error != null && snapshot == null)
                LiveErrorCard(message: data.errorMessage, onRetry: data.reload)
              else if (batches.isEmpty)
                const EmptyState(
                  icon: Icons.route_outlined,
                  title: 'No routes available',
                  message:
                      'Once a farmer marks an order packed it shows up here.',
                )
              else
                for (var index = 0; index < batches.length; index++) ...[
                  PoolCard(
                    route: batches[index].route,
                    badge: _badge(index, batches[index]),
                    orders: batches[index].orderCount,
                    farms: batches[index].farmCount,
                    distance: _distanceLabel(batches[index]),
                    pay: formatPeso(batches[index].payout),
                    capacity: batches[index].capacity,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PoolDetailsPage(
                          session: widget.session,
                          batch: batches[index],
                          riderPoint: snapshot?.riderPoint,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
            ],
          ),
        );
      },
    );
  }

  /// Real road distance and ETA once OSRM has answered, otherwise the
  /// straight-line estimate so the card is never blank.
  String _distanceLabel(PooledBatch batch) {
    final route = RouteService.cached(batch.stops);
    if (route == null) return formatKm(batch.distanceKm);
    return '${route.distanceLabel} • ${route.etaLabel}';
  }

  String _badge(int index, PooledBatch batch) {
    if (index == 0) return 'BEST MATCH';
    if (batch.distanceKm > 0 && batch.distanceKm < 15) return 'NEARBY';
    return 'NEW';
  }
}

class PoolDetailsPage extends StatefulWidget {
  const PoolDetailsPage({
    super.key,
    required this.session,
    required this.batch,
    this.riderPoint,
  });

  final AppSession session;
  final PooledBatch batch;
  final LatLng? riderPoint;

  @override
  State<PoolDetailsPage> createState() => _PoolDetailsPageState();
}

class _PoolDetailsPageState extends State<PoolDetailsPage> {
  late final Set<String> _selected = {
    for (final order in widget.batch.orders) order.id,
  };
  RoutePath? _route;
  bool _accepting = false;

  List<AgriOrder> get _chosen =>
      widget.batch.orders.where((order) => _selected.contains(order.id)).toList();

  /// The chosen orders priced as one shared trip, which is what accepting
  /// them pays.
  int get _payout => PoolPricing.riderPayout(_chosen, DeliveryRates.current);

  int get _kilos =>
      _chosen.fold<int>(0, (total, order) => total + order.quantityKg);

  Future<void> _accept() async {
    if (_chosen.isEmpty) return;
    final stops = {for (final order in _chosen) order.buyerId}.length;
    if (!await confirmAction(
      context,
      title: 'Accept this trip?',
      message: '${plural(_chosen.length, 'order')} \u2022 $_kilos kg \u2022 '
          '${plural(stops, 'drop-off')}.\nYou earn ${formatPeso(_payout)}. '
          'You must finish this trip before going offline or taking another.',
      confirmLabel: 'Accept trip',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => _accepting = true);
    try {
      final user = widget.session.user;
      if (user.payoutNumber.isEmpty) {
        throw Exception('Add your GCash or Maya payout number in Profile '
            'before accepting trips.');
      }
      // One trip at a time: the stops, codes and proofs are all per trip.
      final mine = await authService.database.listAgriOrders(riderId: user.id);
      if (mine.any((order) => order.status.isOpen)) {
        throw Exception('Finish your current trip before accepting another.');
      }
      final tripId = await authService.database.acceptTrip(
        orders: _chosen,
        riderId: user.id,
        riderName: user.name,
        riderPhone: user.phone,
        riderVehicle: user.vehicle.isEmpty ? 'Delivery vehicle' : user.vehicle,
        area: widget.batch.area,
      );
      widget.session.bump();
      if (!mounted) return;
      final count = _chosen.length;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: green, size: 48),
          title: const Text('Trip accepted!'),
          content: Text(
            '$count order${count == 1 ? '' : 's'} added to your delivery trip.',
            textAlign: TextAlign.center,
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Start pickup'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) =>
              ActiveTripPage(session: widget.session, tripId: tripId),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _accepting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$error'.replaceFirst('Exception: ', ''),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final stops = buildTripStops(widget.batch.orders, widget.riderPoint);
    final mapStops = [
      for (final stop in stops)
        if (stop.point != null)
          MapStop(
            point: stop.point!,
            label: stop.title,
            icon: stop.isPickup ? Icons.agriculture : Icons.store,
            color: stop.isPickup ? orange : green,
          ),
    ];
    final pickups = stops.where((stop) => stop.isPickup).length;
    final drops = stops.length - pickups;
    return Scaffold(
      appBar: AppBar(title: const Text('Pooled route')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
        children: [
          if (mapStops.isNotEmpty)
            LiveRouteMap(
              stops: mapStops,
              showControls: true,
              onRouteResolved: (route) {
                if (mounted) setState(() => _route = route);
              },
            )
          else
            const EmptyState(
              icon: Icons.map_outlined,
              title: 'No map for this route',
              message: 'These orders have no pinned farm or delivery location.',
            ),
          const SizedBox(height: 18),
          Text(
            widget.batch.route,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, fontFamily: headingFont, fontFamilyFallback: headingFallback,),
          ),
          const SizedBox(height: 5),
          Text(
            '$pickups pickup${pickups == 1 ? '' : 's'} • '
            '$drops drop-off${drops == 1 ? '' : 's'} • '
            'est. ${_route != null ? _route!.etaLabel : formatDuration(Duration(minutes: (widget.batch.distanceKm / 28 * 60).round()))}',
            style: const TextStyle(color: muted),
          ),
          const SizedBox(height: 20),
          SectionTitle(
            title: 'Select orders',
            action: '${(widget.batch.capacity * 100).round()}% capacity',
          ),
          const SizedBox(height: 10),
          for (final order in widget.batch.orders) ...[
            Card(
              child: CheckboxListTile(
                value: _selected.contains(order.id),
                onChanged: (value) => setState(() {
                  if (value == true) {
                    _selected.add(order.id);
                  } else {
                    _selected.remove(order.id);
                  }
                }),
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  order.buyerName,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  '${order.cropName} • ${order.quantityKg} kg\n'
                  'From ${order.farmerName} → ${order.dropArea}',
                ),
                isThreeLine: true,
                // This order's part of the shared trip, not its solo fee.
                secondary: Text(
                  formatPeso(DeliveryPricing.riderPayout(
                    PoolPricing.shares(_chosen, DeliveryRates.current)[
                            order.id] ??
                        order.deliveryFee,
                  )),
                  style: const TextStyle(
                    color: green,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 6),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  MoneyRow(label: 'Selected load', value: '$_kilos kg'),
                  MoneyRow(
                    label: 'Route distance',
                    value: _route != null
                        ? _route!.distanceLabel
                        : formatKm(widget.batch.distanceKm),
                  ),
                  MoneyRow(
                    label: 'Trip earnings',
                    value: formatPeso(_payout),
                    strong: true,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: _chosen.isEmpty || _accepting ? null : _accept,
            style: FilledButton.styleFrom(padding: const EdgeInsets.all(16)),
            child: Text(
              _accepting
                  ? 'Accepting…'
                  : 'Accept ${_chosen.length} order${_chosen.length == 1 ? '' : 's'}  •  ${formatPeso(_payout)}',
            ),
          ),
        ],
      ),
    );
  }
}

/// Turn-by-turn trip runner: live map, current stop, and stop-by-stop
/// confirmation that writes each leg back to the order.
class ActiveTripPage extends StatefulWidget {
  const ActiveTripPage({
    super.key,
    required this.session,
    required this.tripId,
  });

  final AppSession session;
  final String tripId;

  @override
  State<ActiveTripPage> createState() => _ActiveTripPageState();
}

class _ActiveTripPageState extends State<ActiveTripPage> {
  /// Set only when the rider taps a specific stop; otherwise the screen
  /// follows the next unfinished stop on its own.
  int? _pinnedStop;
  bool _busy = false;
  DateTime? _lastBroadcast;
  LatLng? _devicePoint;

  /// Publishing every GPS tick would hammer Firestore; once every 12 seconds
  /// is smooth enough for a buyer watching the pin.
  static const _broadcastGap = Duration(seconds: 12);

  Future<List<AgriOrder>> _loadOrders() async {
    final mine = await authService.database.listAgriOrders(
      riderId: widget.session.user.id,
    );
    final trip = widget.tripId.isEmpty
        ? mine.where((order) => order.status.isOpen).toList()
        : mine.where((order) => order.tripId == widget.tripId).toList();
    return trip.isEmpty
        ? mine.where((order) => order.status.isOpen).toList()
        : trip;
  }

  void _onPosition(position) {
    final now = DateTime.now();
    _devicePoint = LatLng(position.latitude, position.longitude);
    if (_lastBroadcast != null &&
        now.difference(_lastBroadcast!) < _broadcastGap) {
      return;
    }
    _lastBroadcast = now;
    _broadcast(position.latitude, position.longitude);
  }

  Future<void> _broadcast(double latitude, double longitude) async {
    final orders = _liveOrders;
    if (orders.isEmpty) return;
    try {
      await authService.database.broadcastRiderPosition(
        orderIds: orders
            .where((order) => order.status.isOpen)
            .map((order) => order.id)
            .toList(),
        latitude: latitude,
        longitude: longitude,
      );
    } catch (_) {
      // A dropped location ping is not worth interrupting navigation for.
    }
  }

  List<AgriOrder> _liveOrders = const [];

  /// Everyone on this trip a rider might need to report: each farm and each
  /// buyer, once.
  List<ReportTarget> _reportTargets() {
    final seen = <String>{};
    return [
      for (final order in _liveOrders)
        if (seen.add(order.farmerId))
          ReportTarget(
            id: order.farmerId,
            name: order.farmerName,
            role: 'farmer',
          ),
      for (final order in _liveOrders)
        if (seen.add(order.buyerId))
          ReportTarget(
            id: order.buyerId,
            name: order.buyerName,
            role: 'consumer',
          ),
    ];
  }

  /// When each stop first refused this rider's position, for the GPS
  /// override.
  final Map<String, DateTime> _firstMiss = {};

  String _stopKey(TripStop stop) =>
      '${stop.kind.name}-${stop.orders.map((order) => order.id).join(',')}';

  /// Checks the rider is at [stop] with a fresh, non-mocked GPS fix.
  ///
  /// Returns where they are and the result, or null when they may not confirm
  /// yet (the reason has been shown). After [DeliveryProof.gpsOverrideAfter]
  /// of being refused at the same stop they may confirm anyway, and the stop
  /// is marked as confirmed outside the pin.
  Future<({LatLng? here, GeofenceResult geofence})?> _checkPosition(
    TripStop stop,
  ) async {
    final key = _stopKey(stop);
    Position? fix;
    String problem;
    try {
      fix = await GeoService.freshFix();
      problem = '';
    } on TimeoutException {
      problem = 'Could not get a GPS fix. Step outside or near a window and '
          'try again.';
    } catch (error) {
      problem = '$error'.replaceFirst('Exception: ', '');
    }
    LatLng? here;
    GeofenceResult? result;
    if (fix != null) {
      here = LatLng(fix.latitude, fix.longitude);
      _devicePoint = here;
      result = DeliveryProof.checkGeofence(
        rider: here,
        drop: stop.point,
        mocked: fix.isMocked,
        pickup: stop.isPickup,
      );
      if (result.allowed) {
        _firstMiss.remove(key);
        return (here: here, geofence: result);
      }
      if (result.mocked) {
        _fail(result.message);
        return null;
      }
      problem = result.message;
    }

    final now = DateTime.now();
    final firstMiss = _firstMiss.putIfAbsent(key, () => now);
    if (!DeliveryProof.canOverride(firstMiss, now)) {
      final wait = DeliveryProof.gpsOverrideAfter - now.difference(firstMiss);
      _fail('$problem If GPS is wrong here, you can confirm anyway in '
          '${wait.inMinutes + 1} min.');
      return null;
    }
    if (!mounted) return null;
    setState(() => _busy = false);
    final what = stop.isPickup ? 'pickup' : 'delivery';
    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('GPS still can\'t place you here'),
        content: Text(
          '$problem\n\nConfirm anyway? The ${stop.isPickup ? 'farm' : 'buyer'} '
          'and AgriLink support will see that this $what was confirmed '
          'outside the pin.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirm anyway'),
          ),
        ],
      ),
    );
    if (proceed != true) return null;
    return (
      here: here ?? _devicePoint,
      geofence: DeliveryProof.overridden(result?.distanceMetres),
    );
  }

  /// A camera photo for the proof; null if the rider backs out.
  Future<Uint8List?> _takeProofPhoto() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 55,
      maxWidth: 1280,
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    if (bytes.length > 750000) {
      _fail('That photo is too large. Take it again a little further back.');
      return null;
    }
    return bytes;
  }

  /// A pickup counts once the rider is at the farm and has photographed the
  /// load, so the farm can see what left with whom.
  Future<void> _confirmPickup(
    TripStop stop,
    List<AgriOrder> allOrders,
  ) async {
    setState(() => _busy = true);
    final checked = await _checkPosition(stop);
    if (checked == null || !mounted) return;
    setState(() => _busy = false);
    final photo = await _takeProofPhoto();
    if (photo == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final here = checked.here;
      final geofence = checked.geofence;
      final proofId = await authService.database.uploadDeliveryProof(
        orderIds: stop.orders.map((order) => order.id).toList(),
        riderId: widget.session.user.id,
        photo: photo,
        latitude: here?.latitude,
        longitude: here?.longitude,
        distanceMetres: geofence.distanceMetres,
        kind: 'pickup',
        outsidePin: geofence.overridden,
      );
      await _completeStop(stop, allOrders, extra: {
        'pickupProofId': proofId,
        if (geofence.distanceMetres != null)
          'pickupDistanceMetres': geofence.distanceMetres,
        if (geofence.overridden) 'pickupOutsidePin': true,
      });
    } catch (error) {
      _fail('$error'.replaceFirst('Exception: ', ''));
    }
  }

  /// A drop-off only counts once the rider proves three things: they are at
  /// the buyer's pin (fresh, non-mocked GPS), the buyer handed over their code,
  /// and there is a photo of the items at the door.
  Future<void> _confirmDelivery(
    TripStop stop,
    List<AgriOrder> allOrders,
  ) async {
    setState(() => _busy = true);
    final checked = await _checkPosition(stop);
    if (checked == null || !mounted) return;
    final here = checked.here;
    final geofence = checked.geofence;
    setState(() => _busy = false);

    final proof = await showDialog<Uint8List>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DeliveryProofDialog(stop: stop, geofence: geofence),
    );
    if (proof == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final proofId = await authService.database.uploadDeliveryProof(
        orderIds: stop.orders.map((order) => order.id).toList(),
        riderId: widget.session.user.id,
        photo: proof,
        latitude: here?.latitude,
        longitude: here?.longitude,
        distanceMetres: geofence.distanceMetres,
        outsidePin: geofence.overridden,
      );
      await _completeStop(stop, allOrders, extra: {
        'deliveryProofId': proofId,
        if (here != null) 'deliveredLatitude': here.latitude,
        if (here != null) 'deliveredLongitude': here.longitude,
        if (geofence.distanceMetres != null)
          'deliveredDistanceMetres': geofence.distanceMetres,
        if (geofence.overridden) 'deliveredOutsidePin': true,
        'deliveryCodeVerified': DeliveryProof.requiresCode(stop.orders),
      });
    } catch (error) {
      _fail('$error'.replaceFirst('Exception: ', ''));
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _completeStop(
    TripStop stop,
    List<AgriOrder> allOrders, {
    Map<String, dynamic> extra = const {},
  }) async {
    setState(() => _busy = true);
    try {
      final next =
          stop.isPickup ? OrderStatus.pickedUp : OrderStatus.delivered;
      for (final order in stop.orders) {
        await authService.database.advanceOrder(
          order.id,
          next,
          existingTimeline: order.timeline,
          extra: {
            if (_devicePoint != null) 'riderLatitude': _devicePoint!.latitude,
            if (_devicePoint != null)
              'riderLongitude': _devicePoint!.longitude,
            'riderUpdatedAt': DateTime.now().toUtc().toIso8601String(),
            ...extra,
          },
        );
      }

      // Orders still waiting on some other leg, ignoring the ones just
      // handled here and anything the farmer cancelled.
      Iterable<AgriOrder> outstanding(bool Function(AgriOrder) pending) =>
          allOrders.where(
            (order) =>
                !stop.orders.contains(order) &&
                order.status != OrderStatus.cancelled &&
                pending(order),
          );

      if (stop.isPickup) {
        // Once every farm has been visited the whole load is on the road.
        final remainingPickups = outstanding(
          (order) => order.status.step < OrderStatus.pickedUp.step,
        );
        if (remainingPickups.isEmpty) {
          for (final order in allOrders) {
            if (order.status == OrderStatus.delivered ||
                order.status == OrderStatus.cancelled) {
              continue;
            }
            await authService.database.advanceOrder(
              order.id,
              OrderStatus.inTransit,
              existingTimeline: order.timeline,
            );
          }
        }
      } else {
        final remaining = outstanding(
          (order) => order.status != OrderStatus.delivered,
        );
        if (remaining.isEmpty && widget.tripId.isNotEmpty) {
          await authService.database.completeTrip(widget.tripId);
        }
      }

      widget.session.bump();
      if (!mounted) return;
      // Hand the screen back to the auto-advancing next stop.
      setState(() => _pinnedStop = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            stop.isPickup
                ? 'Pickup confirmed at ${stop.title}.'
                : 'Delivered to ${stop.title}.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error'.replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _contact(String scheme, String phone) async {
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No contact number on file.')),
      );
      return;
    }
    final uri = Uri(scheme: scheme, path: phone);
    if (!await launchUrl(uri) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to open $scheme on this device.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Active trip'),
            Text(
              'Live GPS shared with your buyers',
              style: TextStyle(color: muted, fontSize: 11),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Report a problem',
            onPressed: () => showReportSheet(
              context,
              session: widget.session,
              targets: _reportTargets(),
              orderId: _liveOrders.isEmpty ? '' : _liveOrders.first.id,
            ),
            icon: const Icon(Icons.support_agent),
          ),
        ],
      ),
      body: LiveBuilder<List<AgriOrder>>(
        session: widget.session,
        interval: const Duration(seconds: 10),
        load: _loadOrders,
        builder: (context, data) {
          final orders = data.value ?? const <AgriOrder>[];
          _liveOrders = orders;
          if (orders.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(20),
              child: EmptyState(
                icon: Icons.check_circle_outline,
                title: 'Trip complete',
                message: 'All orders on this trip have been delivered.',
              ),
            );
          }
          final stops = buildTripStops(orders, _devicePoint);
          final firstOpen = stops.indexWhere((stop) => !stop.isComplete);
          final pinned = _pinnedStop;
          final index = pinned != null && pinned < stops.length
              ? pinned
              : firstOpen == -1
                  ? stops.length - 1
                  : firstOpen;
          final stop = stops[index];
          final completed = stops.where((s) => s.isComplete).length;
          final pickupsLeft = stops
              .where((s) => s.isPickup && !s.isComplete)
              .length;
          final mapStops = [
            for (final item in stops)
              if (item.point != null && !item.isComplete)
                MapStop(
                  point: item.point!,
                  label: item.title,
                  icon: item.isPickup ? Icons.agriculture : Icons.store,
                  color: item.isPickup ? orange : green,
                ),
          ];
          void navigate() => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => RiderNavigationPage(
                    stops: mapStops,
                    stop: stop,
                    onPosition: _onPosition,
                  ),
                ),
              );

          return LiveRefreshView(
            loading: data.loading,
            onRefresh: data.reload,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
              children: [
                LiveRouteMap(
                  stops: mapStops,
                  followMe: true,
                  focusPoint: stop.point,
                  onPosition: _onPosition,
                  onExpand: mapStops.isEmpty ? null : navigate,
                  height: 300,
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Pill(
                              icon: stop.isPickup
                                  ? Icons.inventory_2
                                  : Icons.flag,
                              text: stop.label,
                              color: stop.isPickup ? orange : green,
                            ),
                            const Spacer(),
                            Text(
                              'Stop ${index + 1} of ${stops.length}',
                              style: const TextStyle(color: muted),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          stop.title,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700, fontFamily: headingFont, fontFamilyFallback: headingFallback,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          stop.address.isEmpty
                              ? 'No address on file'
                              : stop.address,
                          style: const TextStyle(color: muted, height: 1.4),
                        ),
                        if (stop.point != null && _devicePoint != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            '${formatKm(GeoService.exactKm(_devicePoint!, stop.point!))} away',
                            style: const TextStyle(
                              color: green,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Icon(
                              Icons.person_outline,
                              color: green,
                              size: 18,
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                stop.contactName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            IconButton.filledTonal(
                              tooltip: 'Call contact',
                              onPressed: () => _contact('tel', stop.phone),
                              icon: const Icon(Icons.call, size: 20),
                            ),
                            const SizedBox(width: 5),
                            IconButton.filledTonal(
                              tooltip: 'Message contact',
                              onPressed: () => _contact('sms', stop.phone),
                              icon: const Icon(
                                Icons.message_outlined,
                                size: 20,
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.inventory_2_outlined,
                              color: muted,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${stop.itemsSummary}\nTotal ${stop.totalKg} kg',
                                style: const TextStyle(height: 1.4),
                              ),
                            ),
                          ],
                        ),
                        if (!stop.isPickup &&
                            stop.orders.every((o) => o.isPaymentSecured)) ...[
                          const SizedBox(height: 10),
                          const Pill(
                            icon: Icons.verified,
                            text: 'ALREADY PAID • DO NOT COLLECT CASH',
                            color: green,
                          ),
                        ],
                        const SizedBox(height: 14),
                        LinearProgressIndicator(
                          value: completed / stops.length,
                          minHeight: 8,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '$completed of ${stops.length} stops complete',
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                if (stop.point != null) ...[
                  FilledButton.icon(
                    onPressed: navigate,
                    icon: const Icon(Icons.navigation),
                    label: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Text('Navigate in AgriLink'),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () =>
                        openNavigation(stop.point!, from: _devicePoint),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('Open in Google Maps instead'),
                  ),
                ],
                const SizedBox(height: 20),
                const Text(
                  'Route stops',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18, fontFamily: headingFont, fontFamilyFallback: headingFallback,),
                ),
                const SizedBox(height: 10),
                for (var i = 0; i < stops.length; i++) ...[
                  Card(
                    child: ListTile(
                      onTap: () => setState(() => _pinnedStop = i),
                      title: Text(
                        stops[i].title,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        '${stops[i].label} • ${stops[i].totalKg} kg\n'
                        '${stops[i].address.isEmpty ? 'No address' : stops[i].address}',
                      ),
                      isThreeLine: true,
                      leading: CircleAvatar(
                        backgroundColor: stops[i].isComplete
                            ? green
                            : i == index
                                ? orange
                                : canvas,
                        foregroundColor: stops[i].isComplete || i == index
                            ? Colors.white
                            : ink,
                        child: stops[i].isComplete
                            ? const Icon(Icons.check, size: 20)
                            : Text('${i + 1}'),
                      ),
                      trailing: i == index
                          ? const Icon(Icons.navigation, color: green)
                          : const Icon(Icons.chevron_right),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 6),
                if (!stop.isComplete && !(!stop.isPickup && pickupsLeft > 0))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      stop.isPickup
                          ? 'Tapping below checks you are within '
                              '${DeliveryProof.geofenceMetres.round()} m of '
                              'the farm and opens the camera for a photo of '
                              'the load.'
                          : 'Tapping below checks you are within '
                              '${DeliveryProof.geofenceMetres.round()} m of '
                              'the buyer, then asks for their code and a '
                              'photo.',
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                  ),
                FilledButton.icon(
                  onPressed: _busy || stop.isComplete
                      ? null
                      : !stop.isPickup && pickupsLeft > 0
                          ? null
                          : stop.isPickup
                              ? () => _confirmPickup(stop, orders)
                              : () => _confirmDelivery(stop, orders),
                  icon: const Icon(Icons.check_circle_outline),
                  label: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      stop.isComplete
                          ? 'Stop already completed'
                          : !stop.isPickup && pickupsLeft > 0
                              ? 'Finish $pickupsLeft pickup'
                                  '${pickupsLeft == 1 ? '' : 's'} first'
                              : stop.isPickup
                                  ? 'Confirm pickup & continue'
                                  : 'Verify & confirm delivery',
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Collects the buyer's code and a photo of the items at the door. Returns
/// the photo once both check out; the code itself never leaves this dialog.
class _DeliveryProofDialog extends StatefulWidget {
  const _DeliveryProofDialog({required this.stop, required this.geofence});

  final TripStop stop;
  final GeofenceResult geofence;

  @override
  State<_DeliveryProofDialog> createState() => _DeliveryProofDialogState();
}

class _DeliveryProofDialogState extends State<_DeliveryProofDialog> {
  final _code = TextEditingController();
  Uint8List? _photo;
  String? _error;

  bool get _needsCode => DeliveryProof.requiresCode(widget.stop.orders);

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _takePhoto() async {
    // Camera only: a gallery picture could have been taken anywhere, any day.
    final file = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 55,
      maxWidth: 1280,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() {
      if (bytes.length > 750000) {
        _error = 'That photo is too large. Take it again a little further '
            'back.';
      } else {
        _photo = bytes;
        _error = null;
      }
    });
  }

  void _submit() {
    if (_needsCode &&
        !DeliveryProof.codeMatches(widget.stop.orders, _code.text)) {
      setState(() => _error = 'That code does not match. Ask '
          '${widget.stop.contactName} for the code shown in their app.');
      return;
    }
    if (_photo == null) {
      setState(() => _error = 'Take a photo of the items at the drop-off.');
      return;
    }
    Navigator.pop(context, _photo);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Proof of delivery'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.where_to_vote, color: green, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.geofence.message,
                    style: const TextStyle(
                      color: green,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_needsCode) ...[
              Text(
                'Ask ${widget.stop.contactName} for the delivery code in '
                'their AgriLink app.',
                style: const TextStyle(height: 1.4),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                maxLength: DeliveryProof.codeLength,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 26,
                  letterSpacing: 12,
                  fontWeight: FontWeight.w700, fontFamily: headingFont, fontFamilyFallback: headingFallback,
                ),
                decoration: const InputDecoration(
                  labelText: 'Delivery code',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 14),
            ],
            if (_photo != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  _photo!,
                  height: 160,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _takePhoto,
              icon: const Icon(Icons.photo_camera_outlined),
              label: Text(
                _photo == null ? 'Take photo of items' : 'Retake photo',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(color: Colors.red, height: 1.4),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Confirm delivery'),
        ),
      ],
    );
  }
}

class RiderTrips extends StatelessWidget {
  const RiderTrips({super.key, required this.session});

  final AppSession session;

  @override
  Widget build(BuildContext context) {
    return LiveBuilder<RiderSnapshot>(
      session: session,
      load: () => RiderSnapshot.load(session.user.id),
      builder: (context, data) {
        final snapshot = data.value;
        final delivered = snapshot?.delivered ?? const <AgriOrder>[];
        final grouped = <String, List<AgriOrder>>{};
        for (final order in delivered) {
          grouped
              .putIfAbsent(order.tripId.isEmpty ? order.id : order.tripId, () => [])
              .add(order);
        }
        final trips = grouped.values.toList()
          ..sort((a, b) {
            final left = b.first.timeline[OrderStatus.delivered.wire] ??
                DateTime(1970);
            final right = a.first.timeline[OrderStatus.delivered.wire] ??
                DateTime(1970);
            return left.compareTo(right);
          });
        return LiveRefreshView(
          loading: data.loading,
          onRefresh: data.reload,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const PageHeader(
                eyebrow: 'DELIVERY HISTORY',
                title: 'My Trips',
                subtitle: 'Your completed pooled routes and earnings.',
              ),
              const SizedBox(height: 22),
              if (data.error != null && snapshot == null)
                LiveErrorCard(message: data.errorMessage, onRetry: data.reload)
              else if (trips.isEmpty)
                const EmptyState(
                  icon: Icons.route_outlined,
                  title: 'No completed trips yet',
                  message:
                      'Finished deliveries and what you earned appear here.',
                )
              else
                for (final trip in trips) ...[
                  TripHistoryTile(
                    route: '${trip.first.pickupArea} → ${trip.first.dropArea}',
                    date: () {
                      final at =
                          trip.first.timeline[OrderStatus.delivered.wire];
                      return at == null
                          ? 'Completed'
                          : '${formatRelativeDay(at)} • ${formatClock(at)}';
                    }(),
                    orders:
                        '${trip.length} order${trip.length == 1 ? '' : 's'} • '
                        '${trip.fold<int>(0, (sum, order) => sum + order.quantityKg)} kg',
                    amount: formatPeso(
                      trip.fold<int>(
                        0,
                        (sum, order) => sum + order.riderPayout,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
            ],
          ),
        );
      },
    );
  }
}

class RiderProfile extends StatelessWidget {
  const RiderProfile({super.key, required this.session});

  final AppSession session;

  @override
  Widget build(BuildContext context) {
    final user = session.user;
    return LiveBuilder<RiderSnapshot>(
      session: session,
      load: () => RiderSnapshot.load(user.id),
      builder: (context, data) {
        final snapshot = data.value;
        final delivered = snapshot?.delivered.length ?? 0;
        final assigned = snapshot?.mine.length ?? 0;
        // Trips still on the road are neither completed nor failed yet.
        final finished = snapshot?.mine
                .where((order) => !order.status.isOpen)
                .length ??
            0;
        final completion =
            finished == 0 ? 0 : (delivered / finished * 100).round();
        final earned = snapshot?.delivered ?? const <AgriOrder>[];
        final paidOut = earned
            .where((order) => order.isRiderPaid)
            .fold<int>(0, (sum, order) => sum + order.riderPayout);
        final unpaid = earned
            .where((order) => !order.isRiderPaid)
            .fold<int>(0, (sum, order) => sum + order.riderPayout);
        final rating = RatingSummary.of(
          (snapshot?.mine ?? const <AgriOrder>[]).map((o) => o.riderRating),
        );
        return LiveRefreshView(
          loading: data.loading,
          onRefresh: data.reload,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              PageHeader(
                eyebrow: 'VERIFIED RIDER',
                title: user.name,
                subtitle: '${user.email} • ${user.phone}',
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: StatCard(
                      icon: Icons.account_balance_wallet_outlined,
                      label: 'Lifetime earnings',
                      value: formatPeso(snapshot?.lifetimeEarnings ?? 0),
                      tint: lightGreen,
                      color: green,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatCard(
                      icon: Icons.local_shipping_outlined,
                      label: 'Deliveries',
                      value: '$delivered',
                      tint: const Color(0xFFFFF1DD),
                      color: orange,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ProfileTile(
                icon: Icons.local_shipping_outlined,
                title: 'Vehicle',
                subtitle:
                    user.vehicle.isEmpty ? 'Add your vehicle' : user.vehicle,
                onTap: () => openProfileEditor(context, session),
              ),
              ProfileTile(
                icon: Icons.account_balance_wallet_outlined,
                title: 'Payout number',
                subtitle: user.payoutNumber.isEmpty
                    ? 'Add your GCash / Maya number'
                    : user.payoutNumber,
                onTap: () => openProfileEditor(context, session),
              ),
              ProfileTile(
                icon: Icons.bar_chart,
                title: 'Performance',
                subtitle: assigned == 0
                    ? 'No trips yet'
                    : finished == 0
                        ? '$assigned accepted • none finished yet'
                        : '$completion% completed • $assigned accepted',
                onTap: () {},
              ),
              ProfileTile(
                icon: Icons.request_quote_outlined,
                title: 'Payouts',
                subtitle: '${formatPeso(paidOut)} paid • '
                    '${formatPeso(unpaid)} awaiting payout',
                onTap: () {},
              ),
              ProfileTile(
                icon: Icons.star_outline,
                title: 'Buyer rating',
                subtitle: rating.label,
                onTap: () {},
              ),
              ProfileTile(
                icon: Icons.badge_outlined,
                title: 'Rider documents',
                subtitle: user.isApproved
                    ? 'License and vehicle verified'
                    : 'Under review',
                onTap: () {},
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => signOut(context),
                icon: const Icon(Icons.logout),
                label: const Text('Log out'),
              ),
            ],
          ),
        );
      },
    );
  }
}
