import 'dart:async';

import 'package:flutter/material.dart';

import 'app.dart';
import 'services/phone_alerts.dart';

export 'app.dart';
export 'screens/auth_screens.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Phone notifications for new orders, trips, deliveries and reports.
  unawaited(PhoneAlerts.start());
  runApp(const AgriLinkApp());
}
