import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app.dart';
import '../models/agri_models.dart';
import '../services/geo.dart';
import '../services/session.dart';
import '../utils/app_colors.dart';
import '../widgets/live_data.dart';
import '../widgets/live_map.dart';
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
    final batches = grouped.entries
        .map((entry) => PooledBatch(
              area: entry.key,
              orders: entry.value,
              distanceKm: _batchDistance(entry.value),
            ))
        .toList();
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

  /// Rough end-to-end length: rider to the farthest farm, then out to the town.
  double _batchDistance(List<AgriOrder> orders) {
    var total = 0.0;
    final farms = <LatLng>[];
    for (final order in orders) {
      final pickup = order.pickupPoint;
      if (pickup != null && !farms.contains(pickup)) farms.add(pickup);
    }
    var cursor = riderPoint ?? (farms.isNotEmpty ? farms.first : null);
    for (final farm in farms) {
      if (cursor != null) total += GeoService.distanceKm(cursor, farm);
      cursor = farm;
    }
    for (final order in orders) {
      final drop = order.dropPoint;
      if (drop != null && cursor != null) {
        total += GeoService.distanceKm(cursor, drop);
        cursor = drop;
      }
    }
    return total;
  }

  static Future<RiderSnapshot> load(String riderId) async {
    final results = await Future.wait([
      authService.database.listAgriOrders(),
      authService.database.listTrips(riderId: riderId),
      GeoService.tryCurrentPoint(),
    ]);
    final all = results[0] as List<AgriOrder>;
    return RiderSnapshot(
      pool: all
          .where((order) =>
              order.status == OrderStatus.readyForPickup && !order.hasRider)
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
  }

  Future<void> _setOnline(bool value) async {
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
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Badge(
                    isLabelVisible: batches.isNotEmpty,
                    label: Text('${batches.length}'),
                    child: IconButton.filledTonal(
                      onPressed: onOpenPool,
                      icon: const Icon(Icons.notifications_none),
                    ),
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
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            online
                                ? batches.isEmpty
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
                      fontWeight: FontWeight.w900,
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
                    ? '${next.title}${next.point != null && riderPoint != null ? ' • ${formatKm(GeoService.distanceKm(riderPoint!, next.point!))}' : ''}'
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

  @override
  Widget build(BuildContext context) {
    return LiveBuilder<RiderSnapshot>(
      session: widget.session,
      load: () => RiderSnapshot.load(widget.session.user.id),
      builder: (context, data) {
        final snapshot = data.value;
        final batches =
            snapshot == null ? const <PooledBatch>[] : snapshot.batches(_sort);
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
                            fontWeight: FontWeight.w900,
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
                    distance: formatKm(batches[index].distanceKm),
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

  int get _payout =>
      _chosen.fold<int>(0, (total, order) => total + order.riderPayout);

  int get _kilos =>
      _chosen.fold<int>(0, (total, order) => total + order.quantityKg);

  Future<void> _accept() async {
    if (_chosen.isEmpty) return;
    setState(() => _accepting = true);
    try {
      final user = widget.session.user;
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
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
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
                secondary: Text(
                  formatPeso(order.riderPayout),
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

  Future<void> _completeStop(TripStop stop, List<AgriOrder> allOrders) async {
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
              farmerId: _liveOrders.isEmpty ? '' : _liveOrders.first.farmerId,
              farmerName:
                  _liveOrders.isEmpty ? '' : _liveOrders.first.farmerName,
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

          return LiveRefreshView(
            loading: data.loading,
            onRefresh: data.reload,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
              children: [
                LiveRouteMap(
                  stops: [
                    for (final item in stops)
                      if (item.point != null && !item.isComplete)
                        MapStop(
                          point: item.point!,
                          label: item.title,
                          icon: item.isPickup ? Icons.agriculture : Icons.store,
                          color: item.isPickup ? orange : green,
                        ),
                  ],
                  followMe: true,
                  focusPoint: stop.point,
                  onPosition: _onPosition,
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
                            fontWeight: FontWeight.w900,
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
                            '${formatKm(GeoService.distanceKm(_devicePoint!, stop.point!))} away',
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
                if (stop.point != null)
                  OutlinedButton.icon(
                    onPressed: () =>
                        openNavigation(stop.point!, from: _devicePoint),
                    icon: const Icon(Icons.navigation_outlined),
                    label: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Text('Open turn-by-turn navigation'),
                    ),
                  ),
                const SizedBox(height: 20),
                const Text(
                  'Route stops',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
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
                FilledButton.icon(
                  onPressed: _busy || stop.isComplete
                      ? null
                      : !stop.isPickup && pickupsLeft > 0
                          ? null
                          : () => _completeStop(stop, orders),
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
                                  : 'Confirm delivery & continue',
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
        final completion =
            assigned == 0 ? 0 : (delivered / assigned * 100).round();
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
                icon: Icons.two_wheeler_outlined,
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
                    : '$completion% completion • $assigned accepted',
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
