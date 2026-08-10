import 'package:latlong2/latlong.dart';

/// Every state an order can be in, from checkout to hand-off.
///
/// [wire] is the value stored in Firestore. The older documents in the project
/// used `paid_preparing`, so that string stays as the wire value for
/// [OrderStatus.preparing] and [parse] accepts the other legacy spellings.
enum OrderStatus {
  placed('placed', 'Order placed'),
  preparing('paid_preparing', 'Farmer packing'),
  readyForPickup('ready_for_pickup', 'Ready for pickup'),
  riderAssigned('rider_assigned', 'Rider assigned'),
  pickedUp('picked_up', 'Picked up from farm'),
  inTransit('in_transit', 'On the way'),
  delivered('delivered', 'Delivered'),
  cancelled('cancelled', 'Cancelled');

  const OrderStatus(this.wire, this.label);

  final String wire;
  final String label;

  static OrderStatus parse(Object? value) {
    final raw = '${value ?? ''}'.trim().toLowerCase();
    for (final status in OrderStatus.values) {
      if (status.wire == raw) return status;
    }
    return switch (raw) {
      'pending' || 'new' || 'paid' => OrderStatus.placed,
      'preparing' || 'packing' => OrderStatus.preparing,
      'packed' || 'ready' => OrderStatus.readyForPickup,
      'assigned' || 'accepted' => OrderStatus.riderAssigned,
      'delivering' || 'on_the_way' => OrderStatus.inTransit,
      'completed' || 'done' => OrderStatus.delivered,
      _ => OrderStatus.placed,
    };
  }

  bool get isOpen => this != delivered && this != cancelled;

  /// Waiting on the rider network rather than on the farm.
  bool get isWithRider =>
      this == riderAssigned || this == pickedUp || this == inTransit;

  /// Position in the consumer-facing progress timeline.
  int get step => switch (this) {
        placed => 0,
        preparing => 1,
        readyForPickup => 2,
        riderAssigned => 3,
        pickedUp => 4,
        inTransit => 5,
        delivered => 6,
        cancelled => -1,
      };
}

/// Fee model shared by checkout (what the buyer pays) and the rider pool
/// (what the trip is worth). Keeping it in one place stops the two sides of
/// the app from quoting different numbers for the same delivery.
class DeliveryPricing {
  static const baseFare = 60;
  static const perKilometre = 8;
  static const perKiloHandling = 1.5;
  static const riderShare = 0.8;

  static int fee({required double distanceKm, required num quantityKg}) {
    final distance = distanceKm.isFinite && distanceKm > 0 ? distanceKm : 5;
    return (baseFare +
            distance * perKilometre +
            quantityKg * perKiloHandling)
        .round();
  }

  static int riderPayout(num deliveryFee) => (deliveryFee * riderShare).round();
}

/// The produce categories used by the market filter chips.
enum CropCategory {
  leafy('Leafy', '🥬'),
  vegetables('Vegetables', '🍅'),
  fruits('Fruits', '🥭'),
  grains('Grains', '🌾');

  const CropCategory(this.label, this.emoji);

  final String label;
  final String emoji;

  static CropCategory parse(Object? value) {
    final raw = '${value ?? ''}'.trim().toLowerCase();
    for (final category in CropCategory.values) {
      if (category.label.toLowerCase() == raw) return category;
    }
    return CropCategory.vegetables;
  }

  /// Best-effort category for listings saved before categories existed.
  static CropCategory infer(String cropName) {
    final name = cropName.toLowerCase();
    const leafy = ['pechay', 'kangkong', 'cabbage', 'repolyo', 'lettuce',
        'mustasa', 'spinach', 'petsay', 'malunggay'];
    const fruits = ['mango', 'banana', 'papaya', 'pineapple', 'melon',
        'watermelon', 'calamansi', 'lanzones', 'rambutan', 'avocado'];
    const grains = ['rice', 'palay', 'corn', 'mais', 'bigas', 'monggo',
        'beans', 'peanut', 'mani'];
    if (leafy.any(name.contains)) return CropCategory.leafy;
    if (fruits.any(name.contains)) return CropCategory.fruits;
    if (grains.any(name.contains)) return CropCategory.grains;
    return CropCategory.vegetables;
  }
}

/// Emoji stand-in used by the market tiles when a listing has no photo.
String cropEmoji(String cropName) {
  final name = cropName.toLowerCase();
  const table = {
    'pechay': '🥬',
    'cabbage': '🥬',
    'repolyo': '🥬',
    'lettuce': '🥬',
    'kangkong': '🥬',
    'tomato': '🍅',
    'kamatis': '🍅',
    'onion': '🧅',
    'sibuyas': '🧅',
    'garlic': '🧄',
    'bawang': '🧄',
    'carrot': '🥕',
    'potato': '🥔',
    'patatas': '🥔',
    'eggplant': '🍆',
    'talong': '🍆',
    'corn': '🌽',
    'mais': '🌽',
    'rice': '🌾',
    'palay': '🌾',
    'mango': '🥭',
    'banana': '🍌',
    'saging': '🍌',
    'papaya': '🍈',
    'pineapple': '🍍',
    'watermelon': '🍉',
    'chili': '🌶️',
    'sili': '🌶️',
    'pepper': '🫑',
    'cucumber': '🥒',
    'pipino': '🥒',
    'squash': '🎃',
    'kalabasa': '🎃',
    'ampalaya': '🥒',
    'okra': '🌱',
    'ginger': '🫚',
    'luya': '🫚',
  };
  for (final entry in table.entries) {
    if (name.contains(entry.key)) return entry.value;
  }
  return '🌱';
}

double? _toDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}

int _toInt(Object? value) {
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value.trim()) ?? 0;
  return 0;
}

DateTime? _toDate(Object? value) {
  if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
  return null;
}

/// A harvest a farmer has published to the marketplace.
class CropListing {
  const CropListing({
    required this.id,
    required this.farmerId,
    required this.farmerName,
    required this.farmerPhone,
    required this.name,
    required this.category,
    required this.quantityKg,
    required this.pricePerKg,
    required this.moqKg,
    required this.harvestDate,
    required this.farmLocation,
    required this.latitude,
    required this.longitude,
    required this.photoBase64,
    required this.status,
    required this.createdAt,
  });

  factory CropListing.fromMap(Map<String, dynamic> map) {
    final name = '${map['name'] ?? 'Crop'}';
    return CropListing(
      id: '${map['id'] ?? ''}',
      farmerId: '${map['farmerId'] ?? ''}',
      farmerName: '${map['farmerName'] ?? 'Verified farm'}',
      farmerPhone: '${map['farmerPhone'] ?? ''}',
      name: name,
      category: map['category'] != null
          ? CropCategory.parse(map['category'])
          : CropCategory.infer(name),
      quantityKg: _toInt(map['quantityKg']),
      pricePerKg: _toInt(map['pricePerKg']),
      moqKg: _toInt(map['moqKg']) == 0 ? 1 : _toInt(map['moqKg']),
      harvestDate: '${map['harvestDate'] ?? ''}',
      farmLocation: '${map['farmLocation'] ?? ''}',
      latitude: _toDouble(map['farmLatitude']),
      longitude: _toDouble(map['farmLongitude']),
      photoBase64: map['photoBase64'] is String ? map['photoBase64'] : null,
      status: '${map['status'] ?? 'active'}',
      createdAt: _toDate(map['createdAt']),
    );
  }

  final String id;
  final String farmerId;
  final String farmerName;

  /// Copied onto orders so riders can call the farm from an active trip.
  final String farmerPhone;
  final String name;
  final CropCategory category;
  final int quantityKg;
  final int pricePerKg;
  final int moqKg;
  final String harvestDate;
  final String farmLocation;
  final double? latitude;
  final double? longitude;
  final String? photoBase64;
  final String status;
  final DateTime? createdAt;

  String get emoji => cropEmoji(name);
  bool get inStock => quantityKg > 0 && status == 'active';
  LatLng? get point => latitude != null && longitude != null
      ? LatLng(latitude!, longitude!)
      : null;

  /// Straight-line distance from [origin], or null when either side is unpinned.
  double? distanceKmFrom(LatLng? origin) {
    final farm = point;
    if (origin == null || farm == null) return null;
    return const Distance().as(LengthUnit.Kilometer, origin, farm).toDouble();
  }
}

/// One purchase: a buyer, a farmer, a crop, and the delivery that connects them.
class AgriOrder {
  const AgriOrder({
    required this.id,
    required this.reference,
    required this.buyerId,
    required this.buyerName,
    required this.buyerPhone,
    required this.farmerId,
    required this.farmerName,
    required this.farmerPhone,
    required this.cropId,
    required this.cropName,
    required this.quantityKg,
    required this.pricePerKg,
    required this.totalPrice,
    required this.deliveryFee,
    required this.deliveryAddress,
    required this.deliveryLatitude,
    required this.deliveryLongitude,
    required this.farmLocation,
    required this.farmLatitude,
    required this.farmLongitude,
    required this.paymentMethod,
    required this.paymentReference,
    required this.paymentStatus,
    required this.status,
    required this.riderId,
    required this.riderName,
    required this.riderPhone,
    required this.riderVehicle,
    required this.riderLatitude,
    required this.riderLongitude,
    required this.riderUpdatedAt,
    required this.tripId,
    required this.createdAt,
    required this.timeline,
    required this.raw,
  });

  factory AgriOrder.fromMap(Map<String, dynamic> map) {
    final id = '${map['id'] ?? ''}';
    final timeline = <String, DateTime>{};
    final rawTimeline = map['timeline'];
    if (rawTimeline is Map) {
      rawTimeline.forEach((key, value) {
        final parsed = _toDate(value);
        if (parsed != null) timeline['$key'] = parsed;
      });
    }
    return AgriOrder(
      id: id,
      reference: '${map['reference'] ?? _referenceFrom(id)}',
      buyerId: '${map['buyerId'] ?? ''}',
      buyerName: '${map['buyerName'] ?? 'Consumer'}',
      buyerPhone: '${map['buyerPhone'] ?? ''}',
      farmerId: '${map['farmerId'] ?? ''}',
      farmerName: '${map['farmerName'] ?? 'Farm'}',
      farmerPhone: '${map['farmerPhone'] ?? ''}',
      cropId: '${map['cropId'] ?? ''}',
      cropName: '${map['cropName'] ?? 'Crop'}',
      quantityKg: _toInt(map['quantityKg']),
      pricePerKg: _toInt(map['pricePerKg']),
      totalPrice: _toInt(map['totalPrice']),
      deliveryFee: _toInt(map['deliveryFee']),
      deliveryAddress: '${map['deliveryAddress'] ?? ''}',
      deliveryLatitude: _toDouble(map['deliveryLatitude']),
      deliveryLongitude: _toDouble(map['deliveryLongitude']),
      farmLocation: '${map['farmLocation'] ?? ''}',
      farmLatitude: _toDouble(map['farmLatitude']),
      farmLongitude: _toDouble(map['farmLongitude']),
      paymentMethod: '${map['paymentMethod'] ?? ''}',
      paymentReference: '${map['paymentReference'] ?? ''}',
      paymentStatus: '${map['paymentStatus'] ?? ''}',
      status: OrderStatus.parse(map['status']),
      riderId: '${map['riderId'] ?? ''}',
      riderName: '${map['riderName'] ?? ''}',
      riderPhone: '${map['riderPhone'] ?? ''}',
      riderVehicle: '${map['riderVehicle'] ?? ''}',
      riderLatitude: _toDouble(map['riderLatitude']),
      riderLongitude: _toDouble(map['riderLongitude']),
      riderUpdatedAt: _toDate(map['riderUpdatedAt']),
      tripId: '${map['tripId'] ?? ''}',
      createdAt: _toDate(map['createdAt']),
      timeline: timeline,
      raw: map,
    );
  }

  /// Fallback for documents saved before orders carried a reference.
  ///
  /// Ids look like `order-<millis>-<token>`; using the millis segment keeps
  /// this identical to the reference [CloudDatabase.createOrder] writes,
  /// rather than picking up stray digits from the random token.
  static String _referenceFrom(String id) {
    final segments = id.split('-');
    final millis = segments.length > 1 ? int.tryParse(segments[1]) : null;
    final tail = millis != null
        ? millis.remainder(10000)
        : id.hashCode.abs().remainder(10000);
    return '#AG-${tail.toString().padLeft(4, '0')}';
  }

  final String id;
  final String reference;
  final String buyerId;
  final String buyerName;
  final String buyerPhone;
  final String farmerId;
  final String farmerName;
  final String farmerPhone;
  final String cropId;
  final String cropName;
  final int quantityKg;
  final int pricePerKg;
  final int totalPrice;
  final int deliveryFee;
  final String deliveryAddress;
  final double? deliveryLatitude;
  final double? deliveryLongitude;
  final String farmLocation;
  final double? farmLatitude;
  final double? farmLongitude;
  final String paymentMethod;
  final String paymentReference;
  final String paymentStatus;
  final OrderStatus status;
  final String riderId;
  final String riderName;
  final String riderPhone;
  final String riderVehicle;
  final double? riderLatitude;
  final double? riderLongitude;
  final DateTime? riderUpdatedAt;
  final String tripId;
  final DateTime? createdAt;
  final Map<String, DateTime> timeline;
  final Map<String, dynamic> raw;

  String get emoji => cropEmoji(cropName);
  bool get hasRider => riderId.isNotEmpty;
  int get riderPayout => DeliveryPricing.riderPayout(
        deliveryFee > 0 ? deliveryFee : DeliveryPricing.baseFare,
      );
  int get grandTotal => totalPrice + deliveryFee;

  LatLng? get pickupPoint => farmLatitude != null && farmLongitude != null
      ? LatLng(farmLatitude!, farmLongitude!)
      : null;
  LatLng? get dropPoint =>
      deliveryLatitude != null && deliveryLongitude != null
          ? LatLng(deliveryLatitude!, deliveryLongitude!)
          : null;
  LatLng? get riderPoint => riderLatitude != null && riderLongitude != null
      ? LatLng(riderLatitude!, riderLongitude!)
      : null;

  /// Farm-to-door distance for this order, used for fees and ETA copy.
  double get routeKm {
    final from = pickupPoint;
    final to = dropPoint;
    if (from == null || to == null) return 0;
    return const Distance().as(LengthUnit.Kilometer, from, to).toDouble();
  }

  /// Short town name used to group orders into pooled batches.
  String get dropArea => _area(deliveryAddress);
  String get pickupArea => _area(farmLocation);

  static String _area(String address) {
    if (address.trim().isEmpty) return 'Unassigned area';
    final parts = address
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'Unassigned area';
    // Addresses read "Barangay, Town, Province" — the town is the useful key.
    for (final part in parts.reversed) {
      final normalised = part.toLowerCase();
      if (normalised.contains('philippines') ||
          RegExp(r'^\d{4}$').hasMatch(part)) {
        continue;
      }
      if (normalised.contains('city') || parts.length == 1) return part;
    }
    return parts.length >= 2 ? parts[parts.length - 2] : parts.last;
  }
}

/// A crop plus the quantity a buyer wants, held in the market cart.
class CartLine {
  CartLine({required this.crop, required this.quantityKg});

  final CropListing crop;
  int quantityKg;

  int get subtotal => crop.pricePerKg * quantityKg;
}

enum StopKind { pickup, dropoff }

/// One place a rider has to visit during a trip.
class TripStop {
  const TripStop({
    required this.kind,
    required this.title,
    required this.contactName,
    required this.phone,
    required this.address,
    required this.point,
    required this.orders,
  });

  final StopKind kind;
  final String title;
  final String contactName;
  final String phone;
  final String address;
  final LatLng? point;
  final List<AgriOrder> orders;

  bool get isPickup => kind == StopKind.pickup;
  String get label => isPickup ? 'PICKUP' : 'DELIVERY';

  int get totalKg =>
      orders.fold<int>(0, (total, order) => total + order.quantityKg);

  String get itemsSummary => orders
      .map((order) => '${order.cropName} • ${order.quantityKg} kg')
      .join('\n');

  /// The stop is finished once every order on it has moved past this leg.
  /// Cancelled orders no longer need visiting, so they never hold a stop open.
  bool get isComplete => orders.every(
        (order) =>
            order.status == OrderStatus.cancelled ||
            (isPickup
                ? order.status.step >= OrderStatus.pickedUp.step
                : order.status == OrderStatus.delivered),
      );
}

/// A group of packed orders heading to the same town, offered to riders
/// together so one trip can serve several buyers.
class PooledBatch {
  PooledBatch({
    required this.area,
    required this.orders,
    this.distanceKm = 0,
    this.stops = const [],
  });

  final String area;
  final List<AgriOrder> orders;

  /// Straight-line length of [stops]. Shown immediately, then replaced with the
  /// real driving distance once OSRM answers — see `RouteService`.
  final double distanceKm;

  /// Rider → every farm → every drop-off, in visiting order. This is the
  /// waypoint list handed to the routing service.
  final List<LatLng> stops;

  String get key => area;
  int get orderCount => orders.length;
  int get farmCount => orders.map((order) => order.farmerId).toSet().length;
  int get totalKg =>
      orders.fold<int>(0, (total, order) => total + order.quantityKg);
  int get payout =>
      orders.fold<int>(0, (total, order) => total + order.riderPayout);

  String get route {
    final origins = orders.map((order) => order.pickupArea).toSet().toList();
    final origin = origins.length == 1 ? origins.single : '${origins.length} farms';
    return '$origin → $area';
  }

  /// A typical payload for the four-wheel vehicles AgriLink accepts — an
  /// L300, multicab, or pickup — in kilograms.
  static const vehicleCapacityKg = 1000;

  /// How full that load the batch would leave the vehicle.
  double get capacity => (totalKg / vehicleCapacityKg).clamp(0.0, 1.0);

  PooledBatch withDistance(double km) =>
      PooledBatch(area: area, orders: orders, distanceKm: km, stops: stops);
}
