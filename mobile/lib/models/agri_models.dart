import 'package:flutter/material.dart';
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

/// What a delivery costs, worked out from the price of diesel.
///
/// Riders drive four-wheelers (L300, FB vans) from the farm to town and
/// usually come back empty, so the per-kilometre rate has to cover diesel both
/// ways plus something for the rider's time and the van's upkeep. The
/// superadmin updates the diesel price as it moves; everything else follows.
/// The rider keeps [DeliveryPricing.riderShare] of every fee.
class DeliveryRates {
  const DeliveryRates({
    this.dieselPerLitre = 95,
    this.kmPerLitre = 10,
    this.riderMarginPerKm = 5,
    this.baseFare = 250,
    this.perKiloHandling = 1.5,
  });

  factory DeliveryRates.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const DeliveryRates();
    double read(String key, double fallback) {
      final value = _toDouble(map[key]);
      return value == null || value <= 0 ? fallback : value;
    }

    const defaults = DeliveryRates();
    return DeliveryRates(
      dieselPerLitre: read('dieselPerLitre', defaults.dieselPerLitre),
      kmPerLitre: read('kmPerLitre', defaults.kmPerLitre),
      riderMarginPerKm: read('riderMarginPerKm', defaults.riderMarginPerKm),
      baseFare: read('baseFare', defaults.baseFare),
      perKiloHandling: read('perKiloHandling', defaults.perKiloHandling),
    );
  }

  /// The rates in force, refreshed whenever a screen loads them.
  static DeliveryRates current = const DeliveryRates();

  final double dieselPerLitre;
  final double kmPerLitre;
  final double riderMarginPerKm;
  final double baseFare;
  final double perKiloHandling;

  /// Diesel for one kilometre out and one back.
  double get roundTripFuelPerKm => dieselPerLitre / kmPerLitre * 2;

  /// What the rider takes home per kilometre: round-trip diesel plus margin.
  double get riderPerKm => roundTripFuelPerKm + riderMarginPerKm;

  /// What the buyer is charged per kilometre so the rider's share is
  /// [riderPerKm].
  double get perKilometre => riderPerKm / DeliveryPricing.riderShare;

  /// One trip of [distanceKm] carrying [quantityKg].
  int fee({required double distanceKm, required num quantityKg}) {
    final distance = distanceKm.isFinite && distanceKm > 0 ? distanceKm : 5;
    return (baseFare + distance * perKilometre + quantityKg * perKiloHandling)
        .round();
  }

  Map<String, dynamic> toMap() => {
        'dieselPerLitre': dieselPerLitre,
        'kmPerLitre': kmPerLitre,
        'riderMarginPerKm': riderMarginPerKm,
        'baseFare': baseFare,
        'perKiloHandling': perKiloHandling,
      };
}

class DeliveryPricing {
  static const riderShare = 0.8;

  /// Fee used when an old order carries none.
  static const fallbackFee = 250;

  static int riderPayout(num deliveryFee) => (deliveryFee * riderShare).round();
}

/// Shares one trip's cost between the orders riding on it.
///
/// Every buyer pays the full solo fee at checkout because nobody knows yet
/// who else will be on the trip. When a rider takes a pooled trip, the trip is
/// priced once — one base fare, the real route, the total load — and split in
/// proportion to what each buyer paid. Nobody's share is ever more than they
/// paid; the difference goes back to their wallet.
class PoolPricing {
  /// Straight-line length of farms then drop-offs, in visiting order.
  static double routeKm(List<AgriOrder> orders) {
    final stops = <LatLng>[];
    for (final order in orders) {
      final pickup = order.pickupPoint;
      if (pickup != null && !stops.contains(pickup)) stops.add(pickup);
    }
    for (final order in orders) {
      final drop = order.dropPoint;
      if (drop != null && !stops.contains(drop)) stops.add(drop);
    }
    var total = 0.0;
    const distance = Distance();
    for (var index = 0; index < stops.length - 1; index++) {
      total += distance.as(LengthUnit.Kilometer, stops[index], stops[index + 1]);
    }
    return total;
  }

  /// What one trip carrying all of [orders] costs at [rates].
  static int tripCost(List<AgriOrder> orders, DeliveryRates rates) {
    final kilos = orders.fold<int>(0, (sum, order) => sum + order.quantityKg);
    return rates.fee(distanceKm: routeKm(orders), quantityKg: kilos);
  }

  /// Each order's share of the trip, keyed by order id.
  static Map<String, int> shares(List<AgriOrder> orders, DeliveryRates rates) {
    if (orders.isEmpty) return const {};
    final paid = {
      for (final order in orders)
        order.id: order.deliveryFee > 0
            ? order.deliveryFee
            : DeliveryPricing.fallbackFee,
    };
    final totalPaid = paid.values.fold<int>(0, (sum, fee) => sum + fee);
    if (orders.length == 1 || totalPaid == 0) return paid;
    final cost = tripCost(orders, rates);
    if (cost >= totalPaid) return paid;
    return {
      for (final entry in paid.entries)
        entry.key: (cost * entry.value / totalPaid).round().clamp(0, entry.value),
    };
  }

  /// What the rider earns for taking all of [orders] as one trip.
  static int riderPayout(List<AgriOrder> orders, DeliveryRates rates) =>
      DeliveryPricing.riderPayout(
        shares(orders, rates).values.fold<int>(0, (sum, fee) => sum + fee),
      );
}

/// The produce categories used by the market filter chips.
enum CropCategory {
  leafy('Leafy', Icons.eco),
  vegetables('Vegetables', Icons.yard),
  fruits('Fruits', Icons.local_florist),
  grains('Grains', Icons.grass);

  const CropCategory(this.label, this.icon);

  final String label;
  final IconData icon;

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

  bool get inStock => quantityKg > 0 && status == 'active';

  /// Enough for fewer than three minimum orders: time to restock or harvest.
  bool get isLowStock => inStock && quantityKg < moqKg * 3;
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

  // Proof of delivery. Read straight from [raw] because they are only set on
  // orders that reach those steps, and older documents never carry them.

  /// Shown to the buyer, typed in by the rider at the door.
  String get deliveryCode => '${raw['deliveryCode'] ?? ''}';

  /// The photo the rider took at the drop-off, in `mobileDeliveryProofs`.
  String get deliveryProofId => '${raw['deliveryProofId'] ?? ''}';

  /// The photo the rider took when collecting at the farm.
  String get pickupProofId => '${raw['pickupProofId'] ?? ''}';

  /// The rider confirmed away from the pin after GPS kept failing.
  bool get deliveredOutsidePin => raw['deliveredOutsidePin'] == true;
  bool get pickupOutsidePin => raw['pickupOutsidePin'] == true;
  double? get pickupDistanceMetres => _toDouble(raw['pickupDistanceMetres']);

  /// How far the rider was from the buyer's pin when they confirmed.
  double? get deliveredDistanceMetres =>
      _toDouble(raw['deliveredDistanceMetres']);
  bool get deliveryCodeVerified => raw['deliveryCodeVerified'] == true;
  DateTime? get receivedConfirmedAt => _toDate(raw['receivedConfirmedAt']);
  bool get isReceiptConfirmed => receivedConfirmedAt != null;
  bool get isDisputed => raw['deliveryDisputed'] == true;

  // Delivery schedule. Orders saved before scheduling existed carry neither
  // field and are treated as same-day.

  /// How many days ahead of a scheduled delivery the buyer may still cancel.
  static const cancelNoticeDays = 5;

  bool get isScheduled => raw['deliveryType'] == 'scheduled';

  /// The day it is delivered, at local midnight. Same-day orders carry the
  /// day [DeliveryHours] assigned at checkout; orders saved before that have
  /// none.
  DateTime? get deliveryDate {
    final parsed = DateTime.tryParse('${raw['deliveryDate'] ?? ''}');
    return parsed == null ? null : dateOnly(parsed);
  }

  /// Last day the buyer can cancel, or null when they cannot at all.
  DateTime? get cancelDeadline => isScheduled
      ? deliveryDate?.subtract(const Duration(days: cancelNoticeDays))
      : null;

  /// Same-day orders are committed the moment they are paid. A scheduled
  /// order can be cancelled up to [cancelNoticeDays] before delivery, as long
  /// as no rider has taken it.
  bool canBuyerCancel(DateTime now) {
    final deadline = cancelDeadline;
    if (deadline == null || !status.isOpen || hasRider) return false;
    return !dateOnly(now).isAfter(deadline);
  }

  /// Riders only see an order once deliveries open on its delivery day: a
  /// packed order for next week, or one placed at 2 AM, waits until then.
  bool isDueForPickup(DateTime now) {
    final date = deliveryDate;
    return date == null || !now.isBefore(DeliveryHours.opensOn(date));
  }

  /// The day the farm has to have this out: its delivery date, or the day it
  /// was placed for orders older than scheduling.
  DateTime get dueDate =>
      deliveryDate ??
      dateOnly(DeliveryHours.inManila(createdAt ?? DateTime.now()));

  bool isDueBy(DateTime now) => !dueDate.isAfter(dateOnly(now));

  /// Soonest delivery first, then oldest order first.
  static int byDueDate(AgriOrder a, AgriOrder b) {
    final due = a.dueDate.compareTo(b.dueDate);
    if (due != 0) return due;
    return (a.createdAt ?? DateTime(1970)).compareTo(b.createdAt ?? DateTime(1970));
  }

  /// A same-day order placed after the cutoff that rolled over to tomorrow.
  bool get isNextDay {
    final date = deliveryDate;
    final placed = createdAt;
    if (isScheduled || date == null || placed == null) return false;
    return date.isAfter(dateOnly(DeliveryHours.inManila(placed)));
  }

  /// What goes back to the buyer's wallet if this order is cancelled.
  ///
  /// Gateway and wallet payments are confirmed money. A manually submitted
  /// reference only counts once the farm accepted the order, which is the
  /// farm saying it saw the payment.
  int get refundableAmount => isPaymentSecured ? grandTotal : 0;

  /// The buyer's money is really in: confirmed by the gateway or the wallet,
  /// or a manual reference the farm accepted.
  bool get isPaymentSecured =>
      paymentStatus == 'paid' ||
      (paymentStatus == 'submitted' &&
          timeline.containsKey(OrderStatus.preparing.wire));

  /// What came back to the buyer when the trip was shared.
  int get poolRebate => _toInt(raw['poolRebate']);

  // Buyer ratings, 1–5, left after confirming receipt. 0 means not rated.
  int get farmerRating => _toInt(raw['farmerRating']);
  int get riderRating => _toInt(raw['riderRating']);
  bool get isRated => raw['ratedAt'] != null;

  // Payouts the superadmin has sent for a delivered order.
  bool get isFarmerPaid => raw['farmerPaidAt'] != null;
  bool get isRiderPaid => raw['riderPaidAt'] != null;

  int get refundedAmount => _toInt(raw['refundedAmount']);
  bool get isRefunded => refundedAmount > 0;
  String get cancelledBy => '${raw['cancelledBy'] ?? ''}';

  bool get hasRider => riderId.isNotEmpty;
  int get riderPayout => DeliveryPricing.riderPayout(
        deliveryFee > 0 ? deliveryFee : DeliveryPricing.fallbackFee,
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

  /// The town an address belongs to, the key orders are pooled by.
  static String areaOf(String address) => _area(address);

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

DateTime dateOnly(DateTime time) => DateTime(time.year, time.month, time.day);

/// Average of the 1–5 ratings buyers left, ignoring unrated orders.
class RatingSummary {
  const RatingSummary(this.average, this.count);

  factory RatingSummary.of(Iterable<int> ratings) {
    final given = ratings.where((rating) => rating > 0).toList();
    if (given.isEmpty) return const RatingSummary(0, 0);
    return RatingSummary(
      given.reduce((a, b) => a + b) / given.length,
      given.length,
    );
  }

  final double average;
  final int count;

  String get label => count == 0
      ? 'No ratings yet'
      : '${average.toStringAsFixed(1)} \u2605 (${count == 1 ? '1 rating' : '$count ratings'})';
}

/// When deliveries run. Riders work from [opensAt]; an order placed at or
/// after [cutoff] is delivered the next day. Times are the phone's local time.
class DeliveryHours {
  static const opensAt = 6;
  static const cutoff = 18;

  /// Every farm, rider and buyer is in the Philippines, so the 6 AM opening
  /// and 6 PM cutoff are Philippine time whatever zone the phone is set to.
  /// The Philippines has no daylight saving, so a fixed offset is exact.
  static const manilaOffset = Duration(hours: 8);

  /// The Philippine wall-clock reading of [instant], as a plain local
  /// [DateTime] so it compares directly with stored delivery dates.
  static DateTime inManila(DateTime instant) {
    final t = instant.toUtc().add(manilaOffset);
    return DateTime(
        t.year, t.month, t.day, t.hour, t.minute, t.second, t.millisecond);
  }

  /// The current time in the Philippines; what every delivery rule runs on.
  static DateTime manilaNow() => inManila(DateTime.now());

  /// The day a same-day order placed at [now] is delivered. Before 6 AM it is
  /// still today (riders start at 6); from 6 PM it rolls over to tomorrow.
  static DateTime sameDayDate(DateTime now) {
    final today = dateOnly(now);
    return now.hour >= cutoff ? today.add(const Duration(days: 1)) : today;
  }

  static bool pastCutoff(DateTime now) => now.hour >= cutoff;

  /// The earliest date a scheduled order can be booked for: the day after
  /// whatever same-day would give.
  static DateTime firstScheduleDate(DateTime now) =>
      sameDayDate(now).add(const Duration(days: 1));

  static DateTime opensOn(DateTime date) =>
      DateTime(date.year, date.month, date.day, opensAt);
}

/// One movement of money in a buyer's AgriLink wallet.
///
/// The wallet has no stored balance: it is the sum of these entries, so every
/// peso in it can be traced to a cash-in, a payment, or a refund.
class WalletTransaction {
  const WalletTransaction({
    required this.id,
    this.userId = '',
    required this.type,
    required this.amount,
    required this.description,
    required this.reference,
    required this.createdAt,
  });

  factory WalletTransaction.fromMap(Map<String, dynamic> map) =>
      WalletTransaction(
        id: '${map['id'] ?? ''}',
        userId: '${map['userId'] ?? ''}',
        type: WalletEntryType.parse(map['type']),
        amount: _toInt(map['amount']),
        description: '${map['description'] ?? ''}',
        reference: '${map['reference'] ?? ''}',
        createdAt: _toDate(map['createdAt']),
      );

  final String id;
  final String userId;
  final WalletEntryType type;

  /// Signed pesos: positive adds to the balance, negative spends it.
  final int amount;
  final String description;
  final String reference;
  final DateTime? createdAt;
}

enum WalletEntryType {
  cashIn('cash_in', 'Cash in'),
  payment('payment', 'Payment'),
  refund('refund', 'Refund');

  const WalletEntryType(this.wire, this.label);

  final String wire;
  final String label;

  static WalletEntryType parse(Object? value) => WalletEntryType.values
      .firstWhere((type) => type.wire == value, orElse: () => payment);
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
  /// What the rider earns: the trip is priced once and shared, not the sum
  /// of every buyer's solo fee.
  int get payout => PoolPricing.riderPayout(orders, DeliveryRates.current);

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
