import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../models/agri_models.dart';
import '../models/mobile_user.dart';
import 'cloud_database.dart';
import 'notifications.dart';

/// Shows the in-app inbox's updates as phone notifications.
///
/// AgriLink has no server that could push a message, so the phone asks
/// instead: every 30 seconds while the app is open, and about every 15
/// minutes (Android's shortest background interval) after it is closed.
/// Whatever is newer than the last update already shown becomes a
/// notification, using the same [NoticeFeed] as the bell.
class PhoneAlerts {
  static const _task = 'agrilink-check-updates';
  static const _sessionKey = 'agrilink_mobile_session_v1';
  static String _shownKey(String userId) => 'alertsShownUntil:$userId';

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'agrilink_updates',
      'Order and account updates',
      channelDescription: 'New orders, trips, deliveries, refunds and reports',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> _init() async {
    if (_ready || !_supported) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    _ready = true;
  }

  /// Called once at start-up: asks for permission on Android 13+ and keeps
  /// the background check registered.
  static Future<void> start() async {
    if (!_supported) return;
    try {
      await _init();
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      await Workmanager().initialize(alertsCallbackDispatcher);
      await Workmanager().registerPeriodicTask(
        _task,
        _task,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
    } catch (_) {
      // Notifications are a convenience; the app works without them.
    }
  }

  /// The notices the signed-in user would see in their bell right now.
  static Future<List<AppNotice>> noticesFor(
    MobileUser user,
    CloudDatabase db,
  ) async {
    switch (user.role) {
      case MobileRole.consumer:
        return NoticeFeed.forConsumer(
          await db.listAgriOrders(buyerId: user.id),
        );
      case MobileRole.farmer:
        return NoticeFeed.forFarmer(
          await db.listAgriOrders(farmerId: user.id),
        );
      case MobileRole.rider:
        final all = await db.listAgriOrders();
        final now = DeliveryHours.manilaNow();
        return NoticeFeed.forRider(
          all.where((order) => order.riderId == user.id).toList(),
          all
              .where((order) =>
                  order.status == OrderStatus.readyForPickup &&
                  !order.hasRider &&
                  order.isDueForPickup(now))
              .toList(),
        );
      case MobileRole.superadmin:
        final results = await Future.wait([
          db.listAccounts(),
          db.listReports(),
        ]);
        return NoticeFeed.forAdmin(results[0], results[1]);
    }
  }

  /// Shows anything newer than what was last shown for the signed-in user.
  ///
  /// The first check after signing in only records where the user is, so
  /// they are not flooded with their whole order history.
  static Future<void> check({CloudDatabase? database}) async {
    if (!_supported) return;
    try {
      await _init();
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final userId = prefs.getString(_sessionKey);
      if (userId == null) return;
      final db = database ?? CloudDatabase();
      final account = await db.getAccount(userId);
      if (account == null) return;
      final user = MobileUser.fromJson(account);
      if (!user.isApproved) return;

      final notices = await noticesFor(user, db);
      final shownUntil = DateTime.tryParse(prefs.getString(_shownKey(userId)) ?? '');
      final latest = notices.isEmpty
          ? DateTime.now()
          : notices.map((notice) => notice.at).reduce((a, b) => a.isAfter(b) ? a : b);
      if (shownUntil == null) {
        await prefs.setString(_shownKey(userId), latest.toIso8601String());
        return;
      }
      final fresh = notices.where((notice) => notice.at.isAfter(shownUntil)).toList()
        ..sort((a, b) => a.at.compareTo(b.at));
      // A phone that was off for a while gets the latest few, not dozens.
      for (final notice in fresh.skip(fresh.length > 3 ? fresh.length - 3 : 0)) {
        await _plugin.show(
          id: notice.id.hashCode & 0x7fffffff,
          title: notice.title,
          body: notice.body,
          notificationDetails: _details,
        );
      }
      if (fresh.isNotEmpty) {
        await prefs.setString(_shownKey(userId), latest.toIso8601String());
      }
    } catch (_) {
      // Offline or a transient failure: the next check tries again.
    }
  }
}

/// Runs [PhoneAlerts.check] in the background while the app is closed.
@pragma('vm:entry-point')
void alertsCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    DartPluginRegistrant.ensureInitialized();
    await PhoneAlerts.check();
    return true;
  });
}
