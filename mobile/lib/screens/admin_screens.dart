import 'dart:convert';

import 'package:flutter/material.dart';

import '../app.dart';
import '../models/agri_models.dart';
import '../models/mobile_user.dart';
import '../services/geo.dart';
import '../services/session.dart';
import '../utils/app_colors.dart';
import '../widgets/live_data.dart';
import '../widgets/ui_kit.dart';
import 'shared_screens.dart';

class SuperadminShell extends StatefulWidget {
  const SuperadminShell({super.key, required this.session});
  final AppSession session;

  @override
  State<SuperadminShell> createState() => _SuperadminShellState();
}

class _SuperadminShellState extends State<SuperadminShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      SuperadminOverview(
        session: widget.session,
        onOpenVerification: () => setState(() => _index = 1),
        onOpenDisputes: () => setState(() => _index = 2),
      ),
      VerificationQueue(session: widget.session),
      DisputeCenter(session: widget.session),
      SuperadminProfile(session: widget.session),
    ];
    return Scaffold(
      body: SafeArea(child: LiveIndexedStack(index: _index, children: pages)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.monitor_heart_outlined),
            selectedIcon: Icon(Icons.monitor_heart),
            label: 'Overview',
          ),
          NavigationDestination(
            icon: Icon(Icons.verified_user_outlined),
            selectedIcon: Icon(Icons.verified_user),
            label: 'Verify',
          ),
          NavigationDestination(
            icon: Icon(Icons.gavel_outlined),
            selectedIcon: Icon(Icons.gavel),
            label: 'Disputes',
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

/// Network-wide numbers for the operations tab.
class PlatformSnapshot {
  const PlatformSnapshot({
    required this.accounts,
    required this.orders,
    required this.reports,
  });

  final List<Map<String, dynamic>> accounts;
  final List<AgriOrder> orders;
  final List<Map<String, dynamic>> reports;

  List<Map<String, dynamic>> get pending => accounts
      .where((account) => account['verificationStatus'] == 'pending_review')
      .toList();

  int get verifiedUsers => accounts
      .where((account) => account['verificationStatus'] == 'active')
      .length;

  List<Map<String, dynamic>> get openReports =>
      reports.where((report) => report['status'] != 'resolved').toList();

  /// Value of everything delivered in the last 30 days.
  int get monthlyVolume {
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    return orders
        .where((order) =>
            order.status == OrderStatus.delivered &&
            (order.timeline[OrderStatus.delivered.wire] ??
                    order.createdAt ??
                    DateTime(1970))
                .isAfter(cutoff))
        .fold<int>(0, (total, order) => total + order.grandTotal);
  }

  /// Delivered as a share of everything that reached a final state.
  int get fulfilmentRate {
    final finished =
        orders.where((order) => !order.status.isOpen).length;
    if (finished == 0) return 0;
    final delivered =
        orders.where((order) => order.status == OrderStatus.delivered).length;
    return (delivered / finished * 100).round();
  }

  List<AgriOrder> get stalled {
    final cutoff = DateTime.now().subtract(const Duration(hours: 24));
    return orders
        .where((order) =>
            order.status.isOpen &&
            (order.createdAt ?? DateTime.now()).isBefore(cutoff))
        .toList();
  }

  int countPending(String role) =>
      pending.where((account) => account['role'] == role).length;

  static Future<PlatformSnapshot> load() async {
    final results = await Future.wait([
      authService.database.listAccounts(),
      authService.database.listAgriOrders(),
      authService.database.listReports(),
    ]);
    return PlatformSnapshot(
      accounts: results[0] as List<Map<String, dynamic>>,
      orders: results[1] as List<AgriOrder>,
      reports: results[2] as List<Map<String, dynamic>>,
    );
  }
}

class SuperadminOverview extends StatelessWidget {
  const SuperadminOverview({
    super.key,
    required this.session,
    required this.onOpenVerification,
    required this.onOpenDisputes,
  });

  final AppSession session;
  final VoidCallback onOpenVerification;
  final VoidCallback onOpenDisputes;

  @override
  Widget build(BuildContext context) {
    return LiveBuilder<PlatformSnapshot>(
      session: session,
      load: PlatformSnapshot.load,
      builder: (context, data) {
        final snapshot = data.value;
        return LiveRefreshView(
          loading: data.loading,
          onRefresh: data.reload,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const PageHeader(
                eyebrow: 'PLATFORM OPERATIONS',
                title: 'Network Overview',
                subtitle:
                    'Live transaction and delivery health across AgriLink.',
              ),
              const SizedBox(height: 20),
              if (data.error != null && snapshot == null)
                LiveErrorCard(message: data.errorMessage, onRetry: data.reload)
              else ...[
                Row(
                  children: [
                    Expanded(
                      child: MetricCard(
                        icon: Icons.payments,
                        value: formatPeso(snapshot?.monthlyVolume ?? 0),
                        label: 'Monthly volume',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: MetricCard(
                        icon: Icons.route,
                        value: '${snapshot?.fulfilmentRate ?? 0}%',
                        label: 'Fulfillment',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: MetricCard(
                        icon: Icons.groups,
                        value: '${snapshot?.verifiedUsers ?? 0}',
                        label: 'Verified users',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: MetricCard(
                        icon: Icons.warning_amber,
                        value: '${snapshot?.openReports.length ?? 0}',
                        label: 'Open disputes',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const SectionTitle(title: 'Needs attention', action: 'Live'),
                const SizedBox(height: 10),
                if ((snapshot?.pending.length ?? 0) > 0)
                  InkWell(
                    onTap: onOpenVerification,
                    borderRadius: BorderRadius.circular(20),
                    child: ActionCard(
                      icon: Icons.person_search,
                      title:
                          '${snapshot!.pending.length} registration${snapshot.pending.length == 1 ? '' : 's'} pending',
                      subtitle:
                          '${snapshot.countPending('farmer')} farmers • '
                          '${snapshot.countPending('consumer')} consumers • '
                          '${snapshot.countPending('rider')} riders',
                      badge: 'REVIEW',
                    ),
                  ),
                if ((snapshot?.pending.length ?? 0) > 0)
                  const SizedBox(height: 10),
                if ((snapshot?.openReports.length ?? 0) > 0)
                  InkWell(
                    onTap: onOpenDisputes,
                    borderRadius: BorderRadius.circular(20),
                    child: ActionCard(
                      icon: Icons.gavel_outlined,
                      title:
                          '${snapshot!.openReports.length} open dispute${snapshot.openReports.length == 1 ? '' : 's'}',
                      subtitle: 'Reports filed by buyers and riders',
                      badge: 'OPEN',
                    ),
                  ),
                if ((snapshot?.openReports.length ?? 0) > 0)
                  const SizedBox(height: 10),
                if ((snapshot?.stalled.length ?? 0) > 0)
                  ActionCard(
                    icon: Icons.local_shipping_outlined,
                    title:
                        '${snapshot!.stalled.length} order${snapshot.stalled.length == 1 ? '' : 's'} older than 24h',
                    subtitle: 'Still moving through the network',
                    badge: 'DELAYED',
                  ),
                if (snapshot != null &&
                    snapshot.pending.isEmpty &&
                    snapshot.openReports.isEmpty &&
                    snapshot.stalled.isEmpty)
                  const EmptyState(
                    icon: Icons.verified,
                    title: 'Everything is clear',
                    message:
                        'No pending registrations, disputes, or delayed orders.',
                  ),
                const SizedBox(height: 24),
                const SectionTitle(title: 'Recent orders', action: 'Latest'),
                const SizedBox(height: 10),
                if ((snapshot?.orders.length ?? 0) == 0)
                  const EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'No transactions yet',
                    message: 'Orders across the network will show up here.',
                  )
                else
                  for (final order in snapshot!.orders.take(5)) ...[
                    Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: lightGreen,
                          child: Text(order.emoji),
                        ),
                        title: Text(
                          '${order.reference} • ${order.cropName}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          '${order.buyerName} ← ${order.farmerName}\n'
                          '${order.quantityKg} kg • ${order.status.label}',
                        ),
                        isThreeLine: true,
                        trailing: Text(
                          formatPeso(order.grandTotal),
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            color: green,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
              ],
            ],
          ),
        );
      },
    );
  }
}

class VerificationQueue extends StatelessWidget {
  const VerificationQueue({super.key, required this.session});

  final AppSession session;

  @override
  Widget build(BuildContext context) {
    return LiveBuilder<List<Map<String, dynamic>>>(
      session: session,
      load: () => authService.database.listAccounts(),
      builder: (context, data) {
        final accounts = data.value ?? const <Map<String, dynamic>>[];
        final pending = accounts
            .where((a) => a['verificationStatus'] == 'pending_review')
            .toList();
        final reviewed = accounts
            .where((a) =>
                a['verificationStatus'] != 'pending_review' &&
                a['role'] != 'superadmin')
            .toList();
        return LiveRefreshView(
          loading: data.loading,
          onRefresh: data.reload,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const PageHeader(
                eyebrow: 'NETWORK SAFETY',
                title: 'Verification Queue',
                subtitle:
                    'Review identity, business, farm, and rider documents.',
              ),
              const SizedBox(height: 18),
              if (data.error != null && accounts.isEmpty)
                LiveErrorCard(message: data.errorMessage, onRetry: data.reload)
              else if (pending.isEmpty)
                const EmptyState(
                  icon: Icons.verified_user_outlined,
                  title: 'Nothing to review',
                  message: 'New farmer and rider applications land here.',
                )
              else
                for (final account in pending) ...[
                  ApplicantCard(session: session, account: account),
                  const SizedBox(height: 10),
                ],
              if (reviewed.isNotEmpty) ...[
                const SizedBox(height: 14),
                const SectionTitle(title: 'Reviewed accounts', action: ''),
                const SizedBox(height: 10),
                for (final account in reviewed) ...[
                  Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            account['verificationStatus'] == 'active'
                                ? lightGreen
                                : const Color(0xFFFFE7E2),
                        child: Icon(
                          account['verificationStatus'] == 'active'
                              ? Icons.verified
                              : Icons.block,
                          color: account['verificationStatus'] == 'active'
                              ? green
                              : const Color(0xFFB42318),
                        ),
                      ),
                      title: Text(
                        '${account['name']}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        '${account['role']} • ${account['verificationStatus']}',
                      ),
                      trailing: TextButton(
                        onPressed: () => _setStatus(
                          context,
                          account,
                          account['verificationStatus'] == 'active'
                              ? 'suspended'
                              : 'active',
                        ),
                        child: Text(
                          account['verificationStatus'] == 'active'
                              ? 'Suspend'
                              : 'Restore',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _setStatus(
    BuildContext context,
    Map<String, dynamic> account,
    String status,
  ) async {
    await authService.database
        .setVerificationStatus('${account['id']}', status);
    session.bump();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${account['name']} is now $status.')),
    );
  }
}

/// A pending application with its uploaded documents.
class ApplicantCard extends StatefulWidget {
  const ApplicantCard({
    super.key,
    required this.session,
    required this.account,
  });

  final AppSession session;
  final Map<String, dynamic> account;

  @override
  State<ApplicantCard> createState() => _ApplicantCardState();
}

class _ApplicantCardState extends State<ApplicantCard> {
  bool _busy = false;

  Future<void> _decide(String status) async {
    setState(() => _busy = true);
    try {
      await authService.database.setVerificationStatus(
        '${widget.account['id']}',
        status,
      );
      widget.session.bump();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == 'active'
                ? '${widget.account['name']} approved.'
                : '${widget.account['name']} rejected.',
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

  /// Flags an applicant whose upload did not finish, so a missing requirement
  /// is obvious before anyone taps Approve. Accounts registered before this
  /// was recorded simply show nothing.
  String? _requirementSummary(Map<dynamic, dynamic> profile) {
    final required = int.tryParse('${profile['requiredDocuments'] ?? ''}');
    final submitted = int.tryParse('${profile['submittedDocuments'] ?? ''}');
    if (required == null || submitted == null || required == 0) return null;
    return submitted >= required
        ? '🗂 $submitted of $required required documents attached'
        : '⚠️ Only $submitted of $required required documents attached';
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.account;
    final profile = (account['profile'] as Map?) ?? const {};
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: lightGreen,
                  child: Icon(
                    account['role'] == 'rider'
                        ? Icons.two_wheeler
                        : Icons.agriculture,
                    color: green,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${account['name']}',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      Text(
                        '${account['role']} • ${account['email']}',
                        style: const TextStyle(color: muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const Pill(
                  icon: Icons.pending_actions,
                  text: 'PENDING',
                  color: orange,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              [
                if ('${profile['location'] ?? ''}'.isNotEmpty)
                  '📍 ${profile['location']}',
                if ('${profile['vehicle'] ?? ''}'.isNotEmpty)
                  '🛵 ${profile['vehicle']}',
                if ('${profile['payoutNumber'] ?? ''}'.isNotEmpty)
                  '💳 ${profile['payoutNumber']}',
                if ('${profile['secondaryId'] ?? ''}'.isNotEmpty)
                  '🪪 ${profile['secondaryId']}',
                if ('${account['phone'] ?? ''}'.isNotEmpty)
                  '📞 ${account['phone']}',
                if (_requirementSummary(profile) case final summary?) summary,
              ].join('\n'),
              style: const TextStyle(color: muted, height: 1.6, fontSize: 12),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DocumentsPage(
                    userId: '${account['id']}',
                    name: '${account['name']}',
                  ),
                ),
              ),
              icon: const Icon(Icons.folder_open_outlined),
              label: const Text('View submitted documents'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : () => _decide('active'),
                    icon: const Icon(Icons.check),
                    label: const Text('Approve'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _decide('rejected'),
                    icon: const Icon(Icons.close),
                    label: const Text('Reject'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Renders the base64 documents an applicant uploaded at signup.
class DocumentsPage extends StatelessWidget {
  const DocumentsPage({super.key, required this.userId, required this.name});

  final String userId;
  final String name;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('$name • Documents')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: authService.database.listVerificationFiles(userId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final files = snapshot.data ?? const [];
          if (files.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(20),
              child: EmptyState(
                icon: Icons.description_outlined,
                title: 'No documents uploaded',
                message: 'This applicant did not attach any files at signup.',
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              for (final file in files) ...[
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: Text(
                          '${file['type']}'.replaceAll('_', ' ').toUpperCase(),
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                            color: green,
                          ),
                        ),
                      ),
                      if (file['contentBase64'] is String)
                        Image.memory(
                          base64Decode(file['contentBase64'] as String),
                          width: double.infinity,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Padding(
                            padding: EdgeInsets.all(20),
                            child: Text('Preview unavailable.'),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: Text(
                          '${file['filename']}',
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
            ],
          );
        },
      ),
    );
  }
}

class DisputeCenter extends StatelessWidget {
  const DisputeCenter({super.key, required this.session});

  final AppSession session;

  @override
  Widget build(BuildContext context) {
    return LiveBuilder<List<Map<String, dynamic>>>(
      session: session,
      load: () => authService.database.listReports(),
      builder: (context, data) {
        final reports = data.value ?? const <Map<String, dynamic>>[];
        final open =
            reports.where((report) => report['status'] != 'resolved').toList();
        final resolved =
            reports.where((report) => report['status'] == 'resolved').toList();
        return LiveRefreshView(
          loading: data.loading,
          onRefresh: data.reload,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const PageHeader(
                eyebrow: 'RESOLUTION CENTER',
                title: 'Active Disputes',
                subtitle:
                    'Review order evidence and coordinate resolutions.',
              ),
              const SizedBox(height: 18),
              if (data.error != null && reports.isEmpty)
                LiveErrorCard(message: data.errorMessage, onRetry: data.reload)
              else if (open.isEmpty)
                const EmptyState(
                  icon: Icons.gavel_outlined,
                  title: 'No open disputes',
                  message: 'Reports from buyers and riders will appear here.',
                )
              else
                for (final report in open) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Pill(
                                icon: Icons.warning_amber,
                                text: 'OPEN',
                                color: orange,
                              ),
                              const Spacer(),
                              Text(
                                _reportDate(report),
                                style: const TextStyle(
                                  color: muted,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Against ${report['farmerName'] ?? 'a farmer'}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Filed by ${report['reporterName'] ?? 'a user'}'
                            '${report['reporterRole'] == null ? '' : ' (${report['reporterRole']})'}',
                            style: const TextStyle(color: muted, fontSize: 12),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: canvas,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${report['reason'] ?? ''}',
                              style: const TextStyle(height: 1.45),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: () => _resolve(context, report),
                              icon: const Icon(Icons.done_all),
                              label: const Text('Mark resolved'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              if (resolved.isNotEmpty) ...[
                const SizedBox(height: 10),
                const SectionTitle(title: 'Resolved', action: ''),
                const SizedBox(height: 10),
                for (final report in resolved) ...[
                  Card(
                    child: ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: lightGreen,
                        child: Icon(Icons.check, color: green),
                      ),
                      title: Text(
                        'Against ${report['farmerName'] ?? 'a farmer'}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text('${report['resolution'] ?? 'Resolved'}'),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ],
          ),
        );
      },
    );
  }

  String _reportDate(Map<String, dynamic> report) {
    final at = DateTime.tryParse('${report['createdAt'] ?? ''}');
    return at == null ? '' : '${formatRelativeDay(at)} • ${formatClock(at)}';
  }

  Future<void> _resolve(
    BuildContext context,
    Map<String, dynamic> report,
  ) async {
    final notes = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Resolve dispute'),
        content: TextField(
          controller: notes,
          maxLines: 3,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Resolution notes',
            hintText: 'What action was taken?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Resolve'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await authService.database.resolveReport(
      '${report['id']}',
      notes.text.trim().isEmpty ? 'Reviewed by AgriLink' : notes.text.trim(),
    );
    session.bump();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Dispute marked as resolved.')),
    );
  }
}

class SuperadminProfile extends StatelessWidget {
  const SuperadminProfile({super.key, required this.session});

  final AppSession session;

  @override
  Widget build(BuildContext context) {
    final user = session.user;
    return LiveBuilder<PlatformSnapshot>(
      session: session,
      load: PlatformSnapshot.load,
      builder: (context, data) {
        final snapshot = data.value;
        return LiveRefreshView(
          loading: data.loading,
          onRefresh: data.reload,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              PageHeader(
                eyebrow: 'SUPERADMIN',
                title: user.name,
                subtitle: '${user.email} • ${user.phone}',
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: StatCard(
                      icon: Icons.groups_outlined,
                      label: 'Accounts',
                      value: '${snapshot?.accounts.length ?? 0}',
                      tint: lightGreen,
                      color: green,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatCard(
                      icon: Icons.receipt_long_outlined,
                      label: 'Orders',
                      value: '${snapshot?.orders.length ?? 0}',
                      tint: const Color(0xFFFFF1DD),
                      color: orange,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ProfileTile(
                icon: Icons.manage_accounts_outlined,
                title: 'Account details',
                subtitle: 'Name, phone, and contact information',
                onTap: () => openProfileEditor(context, session),
              ),
              ProfileTile(
                icon: Icons.people_outline,
                title: 'Roles on the network',
                subtitle: _roleBreakdown(snapshot),
                onTap: () {},
              ),
              ProfileTile(
                icon: Icons.security,
                title: 'Platform access',
                subtitle: 'Superadmin — full verification and dispute powers',
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

  String _roleBreakdown(PlatformSnapshot? snapshot) {
    if (snapshot == null) return 'Loading…';
    int count(MobileRole role) => snapshot.accounts
        .where((account) => account['role'] == role.name)
        .length;
    return '${count(MobileRole.consumer)} consumers • '
        '${count(MobileRole.farmer)} farmers • '
        '${count(MobileRole.rider)} riders';
  }
}
