import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/agri_models.dart';
import 'geo.dart';

/// One thing that happened that a user should hear about.
class AppNotice {
  const AppNotice({
    required this.id,
    required this.at,
    required this.title,
    required this.body,
    required this.icon,
  });

  final String id;
  final DateTime at;
  final String title;
  final String body;
  final IconData icon;
}

/// Builds each role's inbox from data the app already loads.
///
/// AgriLink has no server to push messages, so instead of storing
/// notifications the feed is derived from the orders' own timelines and
/// stamps: whatever changed since the user last opened the inbox is new.
class NoticeFeed {
  static DateTime? _time(Object? value) =>
      DateTime.tryParse('${value ?? ''}')?.toLocal();

  static List<AppNotice> _sorted(List<AppNotice> notices) =>
      notices..sort((a, b) => b.at.compareTo(a.at));

  static List<AppNotice> forConsumer(List<AgriOrder> orders) {
    final notices = <AppNotice>[];
    for (final order in orders) {
      final what = '${order.reference} • ${order.cropName}';
      for (final entry in order.timeline.entries) {
        final status = OrderStatus.parse(entry.key);
        final (String title, IconData icon)? line = switch (status) {
          OrderStatus.preparing => (
              'The farm is packing your order',
              Icons.inventory_2_outlined
            ),
          OrderStatus.readyForPickup => (
              'Packed and waiting for a rider',
              Icons.inventory_2
            ),
          OrderStatus.riderAssigned => (
              '${order.riderName.isEmpty ? 'A rider' : order.riderName} accepted your delivery',
              Icons.local_shipping_outlined,
            ),
          OrderStatus.inTransit => (
              order.deliveryCode.isEmpty
                  ? 'Your order is on the way'
                  : 'On the way • your delivery code is ${order.deliveryCode}',
              Icons.local_shipping,
            ),
          OrderStatus.delivered => (
              'Delivered • confirm you received it',
              Icons.check_circle_outline
            ),
          OrderStatus.cancelled => (
              order.isRefunded
                  ? 'Cancelled • ${formatPeso(order.refundedAmount)} back in your wallet'
                  : 'Order cancelled',
              Icons.cancel_outlined,
            ),
          _ => null,
        };
        if (line == null) continue;
        notices.add(AppNotice(
          id: '${order.id}:${entry.key}',
          at: entry.value.toLocal(),
          title: line.$1,
          body: what,
          icon: line.$2,
        ));
      }
      final assigned = _time(order.raw['riderAssignedAt']);
      if (order.poolRebate > 0 && assigned != null) {
        notices.add(AppNotice(
          id: '${order.id}:pool',
          at: assigned,
          title:
              'Shared trip • ${formatPeso(order.poolRebate)} back in your wallet',
          body: what,
          icon: Icons.groups_2_outlined,
        ));
      }
    }
    return _sorted(notices);
  }

  static List<AppNotice> forFarmer(List<AgriOrder> orders) {
    final notices = <AppNotice>[];
    for (final order in orders) {
      final what =
          '${order.reference} • ${order.quantityKg} kg ${order.cropName}';
      final placed = order.timeline[OrderStatus.placed.wire] ?? order.createdAt;
      if (placed != null) {
        notices.add(AppNotice(
          id: '${order.id}:placed',
          at: placed.toLocal(),
          title: 'New order from ${order.buyerName} • ${deliveryLabel(order)}',
          body: what,
          icon: Icons.shopping_bag_outlined,
        ));
      }
      final assigned = order.timeline[OrderStatus.riderAssigned.wire];
      if (assigned != null) {
        notices.add(AppNotice(
          id: '${order.id}:rider',
          at: assigned.toLocal(),
          title:
              '${order.riderName.isEmpty ? 'A rider' : order.riderName} is coming for pickup',
          body: what,
          icon: Icons.local_shipping_outlined,
        ));
      }
      final delivered = order.timeline[OrderStatus.delivered.wire];
      if (delivered != null) {
        notices.add(AppNotice(
          id: '${order.id}:delivered',
          at: delivered.toLocal(),
          title: 'Delivered to ${order.buyerName}',
          body: what,
          icon: Icons.check_circle_outline,
        ));
      }
      final cancelled = order.timeline[OrderStatus.cancelled.wire];
      if (cancelled != null && order.cancelledBy == 'buyer') {
        notices.add(AppNotice(
          id: '${order.id}:cancelled',
          at: cancelled.toLocal(),
          title: '${order.buyerName} cancelled their order',
          body: '$what • stock returned to your listing',
          icon: Icons.cancel_outlined,
        ));
      }
      final rated = _time(order.raw['ratedAt']);
      if (rated != null && order.farmerRating > 0) {
        notices.add(AppNotice(
          id: '${order.id}:rated',
          at: rated,
          title: '${order.buyerName} rated you ${order.farmerRating}/5',
          body: what,
          icon: Icons.star_outline,
        ));
      }
      final paid = _time(order.raw['farmerPaidAt']);
      if (paid != null) {
        notices.add(AppNotice(
          id: '${order.id}:paid',
          at: paid,
          title: 'Payout sent • ${formatPeso(order.totalPrice)}',
          body: '$what • ref ${order.raw['farmerPayoutReference'] ?? ''}',
          icon: Icons.request_quote_outlined,
        ));
      }
    }
    return _sorted(notices);
  }

  static List<AppNotice> forRider(
    List<AgriOrder> mine,
    List<AgriOrder> pool,
  ) {
    final notices = <AppNotice>[];
    if (pool.isNotEmpty) {
      final newest = pool
          .map((order) =>
              order.timeline[OrderStatus.readyForPickup.wire] ??
              order.createdAt ??
              DateTime(1970))
          .reduce((a, b) => a.isAfter(b) ? a : b);
      final towns = pool.map((order) => order.dropArea).toSet();
      notices.add(AppNotice(
        id: 'pool:${newest.toIso8601String()}:${pool.length}',
        at: newest.toLocal(),
        title: '${plural(pool.length, 'packed order')} waiting for a rider',
        body: 'Heading to ${towns.join(', ')}',
        icon: Icons.inventory_2_outlined,
      ));
    }
    for (final order in mine) {
      final what = '${order.reference} • ${order.buyerName}';
      final rated = _time(order.raw['ratedAt']);
      if (rated != null && order.riderRating > 0) {
        notices.add(AppNotice(
          id: '${order.id}:rated',
          at: rated,
          title:
              '${order.buyerName} rated your delivery ${order.riderRating}/5',
          body: what,
          icon: Icons.star_outline,
        ));
      }
      final paid = _time(order.raw['riderPaidAt']);
      if (paid != null) {
        notices.add(AppNotice(
          id: '${order.id}:paid',
          at: paid,
          title: 'Payout sent • ${formatPeso(order.riderPayout)}',
          body: '$what • ref ${order.raw['riderPayoutReference'] ?? ''}',
          icon: Icons.request_quote_outlined,
        ));
      }
      final cancelled = order.timeline[OrderStatus.cancelled.wire];
      if (cancelled != null && order.hasRider) {
        notices.add(AppNotice(
          id: '${order.id}:cancelled',
          at: cancelled.toLocal(),
          title: 'An order on your trip was cancelled',
          body: what,
          icon: Icons.cancel_outlined,
        ));
      }
    }
    return _sorted(notices);
  }

  static List<AppNotice> forAdmin(
    List<Map<String, dynamic>> accounts,
    List<Map<String, dynamic>> reports,
  ) {
    final notices = <AppNotice>[];
    for (final account in accounts) {
      if (account['verificationStatus'] != 'pending_review') continue;
      final at = _time(account['updatedAt']) ?? _time(account['createdAt']);
      if (at == null) continue;
      notices.add(AppNotice(
        id: 'account:${account['id']}:${account['updatedAt']}',
        at: at,
        title: '${account['name']} applied as a ${account['role']}',
        body: 'Waiting in the verification queue',
        icon: Icons.person_search,
      ));
    }
    for (final report in reports) {
      final at = _time(report['createdAt']);
      if (at == null) continue;
      notices.add(AppNotice(
        id: 'report:${report['id']}',
        at: at,
        title: 'New dispute from ${report['reporterName'] ?? 'a user'}',
        body: '${report['reason'] ?? ''}',
        icon: Icons.gavel_outlined,
      ));
    }
    return _sorted(notices);
  }

  /// "Same-day" or the scheduled date, short enough for a notice title.
  static String deliveryLabel(AgriOrder order) {
    final date = order.deliveryDate;
    return order.isScheduled && date != null
        ? 'for ${formatDeliveryDate(date)}'
        : 'same-day';
  }
}

/// When the user last opened their inbox, kept on the device.
class NoticeSeen {
  static String _key(String userId) => 'noticesSeen:$userId';

  static Future<DateTime?> load(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return DateTime.tryParse(prefs.getString(_key(userId)) ?? '');
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(String userId, DateTime at) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(userId), at.toIso8601String());
    } catch (_) {}
  }

  static int unread(List<AppNotice> notices, DateTime? seen) => seen == null
      ? notices.length
      : notices.where((notice) => notice.at.isAfter(seen)).length;
}
