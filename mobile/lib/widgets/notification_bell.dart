import 'package:flutter/material.dart';

import '../services/geo.dart';
import '../services/notifications.dart';
import '../services/session.dart';
import '../utils/app_colors.dart';
import 'live_data.dart';
import 'ui_kit.dart';

/// A bell with an unread count that opens the role's inbox.
class NotificationBell extends StatefulWidget {
  const NotificationBell({
    super.key,
    required this.session,
    required this.load,
  });

  final AppSession session;
  final Future<List<AppNotice>> Function() load;

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  DateTime? _seen;

  @override
  void initState() {
    super.initState();
    NoticeSeen.load(widget.session.user.id).then((seen) {
      if (mounted) setState(() => _seen = seen);
    });
  }

  Future<void> _open(List<AppNotice> notices) async {
    final now = DateTime.now();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NotificationsPage(notices: notices, seen: _seen),
      ),
    );
    await NoticeSeen.save(widget.session.user.id, now);
    if (mounted) setState(() => _seen = now);
  }

  @override
  Widget build(BuildContext context) {
    return LiveBuilder<List<AppNotice>>(
      session: widget.session,
      load: widget.load,
      placeholder: const IconButton.filledTonal(
        onPressed: null,
        icon: Icon(Icons.notifications_none),
      ),
      builder: (context, data) {
        final notices = data.value ?? const <AppNotice>[];
        final unread = NoticeSeen.unread(notices, _seen);
        return Badge(
          isLabelVisible: unread > 0,
          label: Text(unread > 99 ? '99+' : '$unread'),
          child: IconButton.filledTonal(
            tooltip: 'Notifications',
            onPressed: () => _open(notices),
            icon: Icon(
              unread > 0
                  ? Icons.notifications_active_outlined
                  : Icons.notifications_none,
            ),
          ),
        );
      },
    );
  }
}

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({
    super.key,
    required this.notices,
    required this.seen,
  });

  final List<AppNotice> notices;
  final DateTime? seen;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: notices.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(20),
              child: EmptyState(
                icon: Icons.notifications_none,
                title: 'Nothing yet',
                message: 'Updates on your orders and account appear here.',
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              itemCount: notices.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final notice = notices[index];
                final unread = seen == null || notice.at.isAfter(seen!);
                return Card(
                  color: unread ? lightGreen : null,
                  child: ListTile(
                    leading: Icon(notice.icon, color: green),
                    title: Text(
                      notice.title,
                      style: TextStyle(
                        fontWeight: unread ? FontWeight.w900 : FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      '${notice.body}\n'
                      '${formatRelativeDay(notice.at)} • ${formatClock(notice.at)}',
                    ),
                    isThreeLine: true,
                  ),
                );
              },
            ),
    );
  }
}
