import 'dart:convert';

import 'package:flutter/material.dart';

import '../app.dart';
import '../models/agri_models.dart';
import '../models/mobile_user.dart';
import '../services/document_check.dart';
import '../services/geo.dart';
import '../services/notifications.dart';
import '../services/session.dart';
import '../utils/app_colors.dart';
import '../widgets/live_data.dart';
import '../widgets/notification_bell.dart';
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
        onOpenAccounts: () => setState(() => _index = 2),
        onOpenReports: () => setState(() => _index = 3),
      ),
      VerificationQueue(session: widget.session),
      AccountsPage(session: widget.session),
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
            icon: Icon(Icons.groups_outlined),
            selectedIcon: Icon(Icons.groups),
            label: 'Accounts',
          ),
          NavigationDestination(
            icon: Icon(Icons.flag_outlined),
            selectedIcon: Icon(Icons.flag),
            label: 'Reports',
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

  int countActive(String role) => accounts
      .where((account) =>
          account['role'] == role && account['verificationStatus'] == 'active')
      .length;

  int get suspended => accounts
      .where((account) => account['verificationStatus'] == 'suspended')
      .length;

  Iterable<AgriOrder> get _delivered =>
      orders.where((order) => order.status == OrderStatus.delivered);

  int get owedToFarmers => _delivered
      .where((order) => !order.isFarmerPaid)
      .fold<int>(0, (sum, order) => sum + order.totalPrice);

  int get owedToRiders => _delivered
      .where((order) => !order.isRiderPaid && order.hasRider)
      .fold<int>(0, (sum, order) => sum + order.riderPayout);

  int countPending(String role) =>
      pending.where((account) => account['role'] == role).length;

  static Future<PlatformSnapshot> load() async {
    final results = await Future.wait([
      authService.database.listAccounts(),
      authService.database.listAgriOrders(),
      authService.database.listReports(),
      authService.database.loadDeliveryRates(),
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
    required this.onOpenAccounts,
    required this.onOpenReports,
  });

  final AppSession session;
  final VoidCallback onOpenVerification;
  final VoidCallback onOpenAccounts;
  final VoidCallback onOpenReports;

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
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(
                    child: PageHeader(
                      eyebrow: 'PLATFORM OPERATIONS',
                      title: 'Network Overview',
                      subtitle:
                          'Accounts and reports across AgriLink.',
                    ),
                  ),
                  NotificationBell(
                    session: session,
                    load: () async {
                      final results = await Future.wait([
                        authService.database.listAccounts(),
                        authService.database.listReports(),
                      ]);
                      return NoticeFeed.forAdmin(results[0], results[1]);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (data.error != null && snapshot == null)
                LiveErrorCard(message: data.errorMessage, onRetry: data.reload)
              else ...[
                Row(
                  children: [
                    Expanded(
                      child: MetricCard(
                        icon: Icons.shopping_basket_outlined,
                        value: '${snapshot?.countActive('consumer') ?? 0}',
                        label: 'Consumers',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: MetricCard(
                        icon: Icons.agriculture,
                        value: '${snapshot?.countActive('farmer') ?? 0}',
                        label: 'Farmers',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: MetricCard(
                        icon: Icons.local_shipping_outlined,
                        value: '${snapshot?.countActive('rider') ?? 0}',
                        label: 'Riders',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: MetricCard(
                        icon: Icons.flag_outlined,
                        value: '${snapshot?.openReports.length ?? 0}',
                        label: 'Open reports',
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
                          '${plural(snapshot.countPending('farmer'), 'farmer')} • '
                          '${plural(snapshot.countPending('consumer'), 'consumer')} • '
                          '${plural(snapshot.countPending('rider'), 'rider')}',
                      badge: 'REVIEW',
                    ),
                  ),
                if ((snapshot?.pending.length ?? 0) > 0)
                  const SizedBox(height: 10),
                if ((snapshot?.openReports.length ?? 0) > 0)
                  InkWell(
                    onTap: onOpenReports,
                    borderRadius: BorderRadius.circular(20),
                    child: ActionCard(
                      icon: Icons.flag_outlined,
                      title:
                          '${snapshot!.openReports.length} open report${snapshot.openReports.length == 1 ? '' : 's'}',
                      subtitle: 'Filed by consumers, farmers, and riders',
                      badge: 'OPEN',
                    ),
                  ),
                if ((snapshot?.openReports.length ?? 0) > 0)
                  const SizedBox(height: 10),
                if ((snapshot?.suspended ?? 0) > 0)
                  InkWell(
                    onTap: onOpenAccounts,
                    borderRadius: BorderRadius.circular(20),
                    child: ActionCard(
                      icon: Icons.block,
                      title: plural(snapshot!.suspended, 'suspended account'),
                      subtitle: 'Review and restore from Accounts',
                      badge: 'PAUSED',
                    ),
                  ),
                if (snapshot != null &&
                    snapshot.pending.isEmpty &&
                    snapshot.openReports.isEmpty)
                  const EmptyState(
                    icon: Icons.verified,
                    title: 'Everything is clear',
                    message: 'No pending registrations or open reports.',
                  ),
                const SizedBox(height: 24),
                const SectionTitle(title: 'Money', action: ''),
                const SizedBox(height: 10),
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PayoutsPage(session: session),
                    ),
                  ),
                  child: ActionCard(
                    icon: Icons.request_quote_outlined,
                    title: 'Payouts',
                    subtitle: snapshot == null
                        ? 'Loading…'
                        : '${formatPeso(snapshot.owedToFarmers)} to farmers • '
                            '${formatPeso(snapshot.owedToRiders)} to riders',
                    badge: 'OWED',
                  ),
                ),
                const SizedBox(height: 10),
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DeliveryRatesPage(session: session),
                    ),
                  ),
                  child: ActionCard(
                    icon: Icons.local_gas_station_outlined,
                    title: 'Delivery pricing',
                    subtitle: 'Diesel ${formatPeso(DeliveryRates.current.dieselPerLitre)}/L • '
                        '${formatPeso(DeliveryRates.current.perKilometre)}/km',
                    badge: 'RATES',
                  ),
                ),
                const SizedBox(height: 10),
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => WalletLedgerPage(session: session),
                    ),
                  ),
                  child: const ActionCard(
                    icon: Icons.account_balance_wallet_outlined,
                    title: 'Buyer wallets',
                    subtitle: 'Cash-ins, payments, refunds, and balances',
                    badge: 'LEDGER',
                  ),
                ),
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
            ],
          ),
        );
      },
    );
  }
}

/// Asks for a reason and suspends [account], or restores it straight away.
/// Shared by the Accounts list and the Reports queue.
Future<void> changeSuspension(
  BuildContext context,
  AppSession session,
  Map<String, dynamic> account, {
  required bool suspend,
  String suggestedReason = '',
}) async {
  var reason = '';
  if (suspend) {
    final controller = TextEditingController(text: suggestedReason);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Suspend ${account['name']}?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              switch (account['role']) {
                'farmer' => 'Their listings leave the marketplace and they '
                    'cannot use the app until restored.',
                'rider' => 'They cannot take trips or use the app until '
                    'restored.',
                _ => 'They cannot order or use the app until restored.',
              },
              style: const TextStyle(color: muted, height: 1.4),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Reason (shown to them)',
                hintText: 'Scam report, repeated no-shows, fake documents…',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB42318),
            ),
            onPressed: () => Navigator.pop(
              dialogContext,
              controller.text.trim().isNotEmpty,
            ),
            child: const Text('Suspend'),
          ),
        ],
      ),
    );
    reason = controller.text.trim();
    controller.dispose();
    if (confirmed != true || reason.isEmpty) return;
  }
  try {
    await authService.database.setAccountSuspended(
      account,
      suspended: suspend,
      reason: reason,
    );
    session.bump();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${account['name']} is ${suspend ? 'suspended' : 'restored'}.',
        ),
      ),
    );
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$error'.replaceFirst('Exception: ', ''))),
    );
  }
}

/// The id a report is filed against; older reports only named a farm.
String reportedAccountId(Map<String, dynamic> report) =>
    '${report['againstId'] ?? report['farmerId'] ?? ''}';

/// Every consumer, farmer and rider, with how often they have been reported,
/// and the switch to suspend or restore them.
class AccountsPage extends StatefulWidget {
  const AccountsPage({super.key, required this.session});

  final AppSession session;

  @override
  State<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends State<AccountsPage> {
  final _search = TextEditingController();
  String _role = '';

  static const _roles = {
    '': 'All',
    'consumer': 'Consumers',
    'farmer': 'Farmers',
    'rider': 'Riders',
  };

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  static Future<({List<Map<String, dynamic>> accounts, Map<String, int> reports})>
      _load() async {
    final results = await Future.wait([
      authService.database.listAccounts(),
      authService.database.listReports(),
    ]);
    final counts = <String, int>{};
    for (final report in results[1]) {
      final id = reportedAccountId(report);
      if (id.isNotEmpty) counts[id] = (counts[id] ?? 0) + 1;
    }
    return (accounts: results[0], reports: counts);
  }

  bool _matches(Map<String, dynamic> account) {
    if (account['role'] == 'superadmin') return false;
    // Applications still waiting are handled on the Verify tab.
    if (account['verificationStatus'] == 'pending_review') return false;
    if (_role.isNotEmpty && account['role'] != _role) return false;
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return true;
    return [account['name'], account['email'], account['phone']]
        .any((field) => '${field ?? ''}'.toLowerCase().contains(query));
  }

  @override
  Widget build(BuildContext context) {
    return LiveBuilder(
      session: widget.session,
      load: _load,
      builder: (context, data) {
        final accounts =
            (data.value?.accounts ?? const <Map<String, dynamic>>[])
                .where(_matches)
                .toList()
              ..sort((a, b) => '${a['name']}'
                  .toLowerCase()
                  .compareTo('${b['name']}'.toLowerCase()));
        final reports = data.value?.reports ?? const <String, int>{};
        return LiveRefreshView(
          loading: data.loading,
          onRefresh: data.reload,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const PageHeader(
                eyebrow: 'NETWORK SAFETY',
                title: 'Accounts',
                subtitle: 'Consumers, farmers, and riders on AgriLink.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Name, email, or phone',
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final entry in _roles.entries)
                    ChoiceChip(
                      label: Text(entry.value),
                      selected: _role == entry.key,
                      onSelected: (_) => setState(() => _role = entry.key),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (data.error != null && data.value == null)
                LiveErrorCard(message: data.errorMessage, onRetry: data.reload)
              else if (accounts.isEmpty)
                const EmptyState(
                  icon: Icons.person_search,
                  title: 'No accounts found',
                  message: 'Try another name or role.',
                )
              else
                for (final account in accounts) ...[
                  _AccountCard(
                    session: widget.session,
                    account: account,
                    reportCount: reports['${account['id']}'] ?? 0,
                  ),
                  const SizedBox(height: 10),
                ],
            ],
          ),
        );
      },
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.session,
    required this.account,
    required this.reportCount,
  });

  final AppSession session;
  final Map<String, dynamic> account;
  final int reportCount;

  @override
  Widget build(BuildContext context) {
    final status = '${account['verificationStatus'] ?? ''}';
    final active = status == 'active';
    final role = '${account['role'] ?? ''}';
    final reason = '${account['statusReason'] ?? ''}';
    final (icon, label) = switch (role) {
      'farmer' => (Icons.agriculture, 'Farmer'),
      'rider' => (Icons.local_shipping, 'Rider'),
      _ => (Icons.shopping_basket_outlined, 'Consumer'),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor:
                      active ? lightGreen : const Color(0xFFFFE7E2),
                  child: Icon(
                    active ? icon : Icons.block,
                    color: active ? green : const Color(0xFFB42318),
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
                        '$label \u2022 ${account['email'] ?? ''}',
                        style: const TextStyle(color: muted, fontSize: 12),
                      ),
                      if ('${account['phone'] ?? ''}'.isNotEmpty)
                        Text(
                          '${account['phone']}',
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                    ],
                  ),
                ),
                Pill(
                  icon: active ? Icons.verified : Icons.block,
                  text: switch (status) {
                    'active' => 'ACTIVE',
                    'suspended' => 'SUSPENDED',
                    'rejected' => 'REJECTED',
                    _ => status.toUpperCase(),
                  },
                  color: active ? green : const Color(0xFFB42318),
                ),
              ],
            ),
            if (reportCount > 0 || reason.isNotEmpty) ...[
              const SizedBox(height: 10),
              if (reportCount > 0)
                Row(
                  children: [
                    const Icon(Icons.flag, size: 15, color: orange),
                    const SizedBox(width: 6),
                    Text(
                      plural(reportCount, 'report'),
                      style: const TextStyle(
                        color: orange,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              if (reason.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Reason: $reason',
                    style: const TextStyle(color: muted, fontSize: 12),
                  ),
                ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                if (role == 'farmer' || role == 'rider')
                  TextButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DocumentsPage(
                          userId: '${account['id']}',
                          name: '${account['name']}',
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.folder_open_outlined, size: 18),
                    label: const Text('Documents'),
                  ),
                const Spacer(),
                if (active)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFB42318),
                    ),
                    onPressed: () => changeSuspension(
                      context,
                      session,
                      account,
                      suspend: true,
                    ),
                    icon: const Icon(Icons.block, size: 18),
                    label: const Text('Suspend'),
                  )
                else if (status == 'suspended')
                  FilledButton.icon(
                    onPressed: () => changeSuspension(
                      context,
                      session,
                      account,
                      suspend: false,
                    ),
                    icon: const Icon(Icons.restore, size: 18),
                    label: const Text('Restore'),
                  ),
              ],
            ),
          ],
        ),
      ),
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
      // The applicant was told they would hear back, so tell them. A failure
      // here must not undo a decision that is already saved.
      var emailed = false;
      try {
        final delivery = await authService.email.sendVerificationDecision(
          email: '${widget.account['email'] ?? ''}',
          name: '${widget.account['name'] ?? ''}',
          approved: status == 'active',
          role: '${widget.account['role'] ?? 'account'}',
        );
        emailed = delivery.sent;
      } catch (_) {
        emailed = false;
      }
      widget.session.bump();
      if (!mounted) return;
      final decision = status == 'active'
          ? '${widget.account['name']} approved.'
          : '${widget.account['name']} rejected.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            emailed ? '$decision Applicant notified by email.' : decision,
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
  (IconData, String)? _requirementSummary(Map<dynamic, dynamic> profile) {
    final required = int.tryParse('${profile['requiredDocuments'] ?? ''}');
    final submitted = int.tryParse('${profile['submittedDocuments'] ?? ''}');
    if (required == null || submitted == null || required == 0) return null;
    return submitted >= required
        ? (
            Icons.folder_outlined,
            '$submitted of $required required documents attached',
          )
        : (
            Icons.warning_amber_rounded,
            'Only $submitted of $required required documents attached',
          );
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
                        ? Icons.local_shipping
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
            for (final (icon, text) in [
              if ('${profile['location'] ?? ''}'.isNotEmpty)
                (Icons.location_on_outlined, '${profile['location']}'),
              if ('${profile['vehicle'] ?? ''}'.isNotEmpty)
                (Icons.local_shipping_outlined, '${profile['vehicle']}'),
              if ('${profile['payoutNumber'] ?? ''}'.isNotEmpty)
                (Icons.account_balance_wallet_outlined,
                    '${profile['payoutNumber']}'),
              if ('${profile['secondaryId'] ?? ''}'.isNotEmpty)
                (Icons.badge_outlined, '${profile['secondaryId']}'),
              if ('${account['phone'] ?? ''}'.isNotEmpty)
                (Icons.phone_outlined, '${account['phone']}'),
              if (_requirementSummary(profile) case final summary?) summary,
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, size: 15, color: muted),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        text,
                        style: const TextStyle(
                          color: muted,
                          height: 1.4,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
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

/// Renders the documents an applicant uploaded, with the screening warnings
/// raised against each one.
///
/// The screening never claims a document is forged. It reports what can be
/// measured — resolution, file weight, how flat the image is, and whether the
/// same picture has been submitted before — and leaves the judgement to the
/// reviewer looking at the photo.
class DocumentsPage extends StatefulWidget {
  const DocumentsPage({super.key, required this.userId, required this.name});

  final String userId;
  final String name;

  @override
  State<DocumentsPage> createState() => _DocumentsPageState();
}

class _DocumentsPageState extends State<DocumentsPage> {
  late Future<List<_ReviewedDocument>> _documents = _load();

  Future<List<_ReviewedDocument>> _load() async {
    final files =
        await authService.database.listVerificationFiles(widget.userId);
    final reviewed = <_ReviewedDocument>[];
    for (final file in files) {
      final duplicates = await authService.database.findDuplicateUploads(
        contentHash: '${file['contentHash'] ?? ''}',
        excludingUserId: widget.userId,
      );
      reviewed.add(
        _ReviewedDocument(
          file: file,
          flags: [
            ...DocumentCheck.decode(file['screeningFlags']),
            if (duplicates.isNotEmpty) DocumentFlag.reusedByAnotherAccount,
          ],
        ),
      );
    }
    return reviewed;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.name} • Documents')),
      body: FutureBuilder<List<_ReviewedDocument>>(
        future: _documents,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: LiveErrorCard(
                message: '${snapshot.error}'.replaceFirst('Exception: ', ''),
                onRetry: () => setState(() => _documents = _load()),
              ),
            );
          }
          final documents = snapshot.data ?? const <_ReviewedDocument>[];
          if (documents.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(20),
              child: EmptyState(
                icon: Icons.description_outlined,
                title: 'No documents uploaded',
                message: 'This applicant did not attach any files at signup.',
              ),
            );
          }
          final flagged = documents.where((d) => d.flags.isNotEmpty).length;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (flagged > 0) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7E8),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFFFD99A)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: orange),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '$flagged of ${documents.length} uploads raised a '
                          'screening warning. Look at the photos yourself '
                          'before approving.',
                          style: const TextStyle(fontSize: 12.5, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
              for (final document in documents) ...[
                _DocumentCard(document: document),
                const SizedBox(height: 14),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ReviewedDocument {
  const _ReviewedDocument({required this.file, required this.flags});

  final Map<String, dynamic> file;
  final List<DocumentFlag> flags;

  String get type => '${file['type']}'.replaceAll('_', ' ').toUpperCase();
  String get filename => '${file['filename'] ?? ''}';
  int get width => (file['width'] as num?)?.toInt() ?? 0;
  int get height => (file['height'] as num?)?.toInt() ?? 0;
  int get size => (file['size'] as num?)?.toInt() ?? 0;

  String get measurements {
    final parts = <String>[
      if (width > 0 && height > 0) '$width x $height px',
      if (size > 0) '${(size / 1024).round()} KB',
    ];
    return parts.join(' • ');
  }
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({required this.document});

  final _ReviewedDocument document;

  @override
  Widget build(BuildContext context) {
    final content = document.file['contentBase64'];
    final suspicious = document.flags.isNotEmpty;
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: suspicious ? orange : const Color(0xFFE6EAE2),
          width: suspicious ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    document.type,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                      color: green,
                    ),
                  ),
                ),
                if (suspicious)
                  const Pill(
                    icon: Icons.warning_amber_rounded,
                    text: 'CHECK',
                    color: orange,
                  ),
              ],
            ),
          ),
          if (content is String)
            InkWell(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => _DocumentViewer(
                    title: document.type,
                    contentBase64: content,
                  ),
                ),
              ),
              child: Image.memory(
                base64Decode(content),
                width: double.infinity,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('Preview unavailable.'),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  document.filename,
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
                if (document.measurements.isNotEmpty)
                  Text(
                    document.measurements,
                    style: const TextStyle(color: muted, fontSize: 11),
                  ),
                for (final flag in document.flags) ...[
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.error_outline, size: 16, color: orange),
                      const SizedBox(width: 7),
                      Expanded(
                        child: RichText(
                          text: TextSpan(
                            style: const TextStyle(
                              color: ink,
                              fontSize: 11.5,
                              height: 1.35,
                            ),
                            children: [
                              TextSpan(
                                text: '${flag.label}. ',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              TextSpan(text: flag.explanation),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (!suspicious) ...[
                  const SizedBox(height: 8),
                  const Row(
                    children: [
                      Icon(Icons.check_circle_outline, size: 16, color: green),
                      SizedBox(width: 7),
                      Text(
                        'No screening warnings',
                        style: TextStyle(color: muted, fontSize: 11.5),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-screen, zoomable view. Small print on a permit is unreadable at card
/// size, and a reviewer has to be able to actually look at it.
class _DocumentViewer extends StatelessWidget {
  const _DocumentViewer({required this.title, required this.contentBase64});

  final String title;
  final String contentBase64;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontSize: 14)),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 6,
          child: Image.memory(base64Decode(contentBase64)),
        ),
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
                title: 'Reports',
                subtitle: 'Review each report, then resolve it or suspend '
                    'the account it is about.',
              ),
              const SizedBox(height: 18),
              if (data.error != null && reports.isEmpty)
                LiveErrorCard(message: data.errorMessage, onRetry: data.reload)
              else if (open.isEmpty)
                const EmptyState(
                  icon: Icons.flag_outlined,
                  title: 'No open reports',
                  message: 'Reports from consumers, farmers, and riders '
                      'will appear here.',
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
                            'About ${_against(report)}',
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

                          if ('${report['orderId'] ?? ''}'.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () => _showProof(
                                  context,
                                  '${report['orderId']}',
                                ),
                                icon: const Icon(Icons.fact_check_outlined),
                                label: const Text('View delivery proof'),
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              if (reportedAccountId(report).isNotEmpty) ...[
                                Expanded(
                                  child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFFB42318),
                                    ),
                                    onPressed: () =>
                                        _suspendReported(context, report),
                                    icon: const Icon(Icons.block, size: 18),
                                    label: const Text('Suspend'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: () => _resolve(context, report),
                                  icon: const Icon(Icons.done_all, size: 18),
                                  label: const Text('Resolve'),
                                ),
                              ),
                            ],
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
                        'About ${_against(report)}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        '${report['resolution'] ?? 'Resolved'}'
                        '${report['refundAmount'] == null ? '' : ' • refunded ${formatPeso(report['refundAmount'] as num)}'}',
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

  /// "Juan Dela Cruz (rider)"; older reports were always about a farm.
  String _against(Map<String, dynamic> report) {
    final name = '${report['againstName'] ?? report['farmerName'] ?? ''}';
    final role = '${report['againstRole'] ?? (report['farmerId'] == null ? '' : 'farmer')}';
    final label = switch (role) {
      'farmer' => 'farm',
      'rider' => 'rider',
      'consumer' => 'buyer',
      _ => '',
    };
    if (name.isEmpty) return 'a general issue';
    return label.isEmpty ? name : '$name ($label)';
  }

  /// Suspends the account a report is about, with the report as the reason.
  Future<void> _suspendReported(
    BuildContext context,
    Map<String, dynamic> report,
  ) async {
    final account =
        await authService.database.getAccount(reportedAccountId(report));
    if (!context.mounted) return;
    if (account == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That account no longer exists.')),
      );
      return;
    }
    if (account['verificationStatus'] == 'suspended') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${account['name']} is already suspended.')),
      );
      return;
    }
    await changeSuspension(
      context,
      session,
      account,
      suspend: true,
      suggestedReason: 'Reported: ${report['reason'] ?? ''}'.trim(),
    );
  }

  String _reportDate(Map<String, dynamic> report) {
    final at = DateTime.tryParse('${report['createdAt'] ?? ''}');
    return at == null ? '' : '${formatRelativeDay(at)} • ${formatClock(at)}';
  }

  /// Puts the rider's drop-off evidence next to the buyer's complaint.
  Future<void> _showProof(BuildContext context, String orderId) async {
    final order = await authService.database.getOrder(orderId);
    if (!context.mounted) return;
    if (order == null || order.status != OrderStatus.delivered) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This order has not been marked delivered.'),
        ),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DeliveryProofCard(order: order),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _resolve(
    BuildContext context,
    Map<String, dynamic> report,
  ) async {
    final notes = TextEditingController();
    final refund = TextEditingController();
    final hasOrder = '${report['orderId'] ?? ''}'.isNotEmpty;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Resolve dispute'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: notes,
                maxLines: 3,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Resolution notes',
                  hintText: 'What action was taken?',
                ),
              ),
              if (hasOrder) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: refund,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Refund to buyer wallet (optional)',
                    prefixText: '₱',
                    helperText: 'e.g. the value of the missing kilos',
                  ),
                ),
              ],
            ],
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
    final resolution =
        notes.text.trim().isEmpty ? 'Reviewed by AgriLink' : notes.text.trim();
    final amount = int.tryParse(refund.text.trim()) ?? 0;
    notes.dispose();
    refund.dispose();
    if (confirmed != true) return;
    try {
      final refunded = await authService.database.resolveReportWithRefund(
        reportId: '${report['id']}',
        resolution: resolution,
        refundAmount: amount,
      );
      session.bump();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            refunded > 0
                ? 'Resolved. ${formatPeso(refunded)} refunded to the buyer\'s '
                    'wallet.'
                : 'Dispute marked as resolved.',
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error'.replaceFirst('Exception: ', ''))),
      );
    }
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
                      icon: Icons.flag_outlined,
                      label: 'Open reports',
                      value: '${snapshot?.openReports.length ?? 0}',
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
                subtitle: 'Superadmin: verification, accounts, and reports',
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
    return '${plural(count(MobileRole.consumer), 'consumer')} • '
        '${plural(count(MobileRole.farmer), 'farmer')} • '
        '${plural(count(MobileRole.rider), 'rider')}';
  }
}

/// What AgriLink owes each farmer and rider for delivered orders, and a way
/// to record that it was sent.
class PayoutsPage extends StatelessWidget {
  const PayoutsPage({super.key, required this.session});

  final AppSession session;

  static Future<({List<AgriOrder> orders, Map<String, String> payoutNumbers})>
      _load() async {
    final results = await Future.wait([
      authService.database.listAgriOrders(),
      authService.database.listAccounts(),
    ]);
    final accounts = results[1] as List<Map<String, dynamic>>;
    return (
      orders: (results[0] as List<AgriOrder>)
          .where((order) => order.status == OrderStatus.delivered)
          .toList(),
      payoutNumbers: {
        for (final account in accounts)
          '${account['id']}':
              '${(account['profile'] as Map?)?['payoutNumber'] ?? ''}',
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Payouts')),
      body: LiveBuilder(
        session: session,
        load: _load,
        builder: (context, data) {
          final value = data.value;
          final delivered = value?.orders ?? const <AgriOrder>[];
          final numbers = value?.payoutNumbers ?? const <String, String>{};

          List<_PayoutGroup> group(String payee) {
            final groups = <String, _PayoutGroup>{};
            for (final order in delivered) {
              final farmer = payee == 'farmer';
              if (farmer ? order.isFarmerPaid : order.isRiderPaid) continue;
              final id = farmer ? order.farmerId : order.riderId;
              if (id.isEmpty) continue;
              final entry = groups.putIfAbsent(
                id,
                () => _PayoutGroup(
                  payee: payee,
                  name: farmer ? order.farmerName : order.riderName,
                  number: numbers[id] ?? '',
                ),
              );
              entry.orders.add(order);
              entry.amount += farmer ? order.totalPrice : order.riderPayout;
            }
            return groups.values.toList()
              ..sort((a, b) => b.amount.compareTo(a.amount));
          }

          final farmers = group('farmer');
          final riders = group('rider');
          return LiveRefreshView(
            loading: data.loading,
            onRefresh: data.reload,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                const Text(
                  'Farmers are owed the produce price of each delivered '
                  'order; riders their share of the delivery fee. Send the '
                  'money by GCash or Maya, then record the reference here.',
                  style: TextStyle(color: muted, height: 1.4),
                ),
                const SizedBox(height: 18),
                if (data.error != null && value == null)
                  LiveErrorCard(
                    message: data.errorMessage,
                    onRetry: data.reload,
                  ),
                for (final (title, groups) in [
                  ('Farmers', farmers),
                  ('Riders', riders),
                ]) ...[
                  SectionTitle(title: title, action: ''),
                  const SizedBox(height: 10),
                  if (groups.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 18),
                      child: Text(
                        'Nothing owed right now.',
                        style: TextStyle(color: muted),
                      ),
                    )
                  else
                    for (final entry in groups)
                      _PayoutCard(session: session, group: entry),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PayoutGroup {
  _PayoutGroup({
    required this.payee,
    required this.name,
    required this.number,
  });

  final String payee;
  final String name;
  final String number;
  final List<AgriOrder> orders = [];
  int amount = 0;
}

class _PayoutCard extends StatefulWidget {
  const _PayoutCard({required this.session, required this.group});

  final AppSession session;
  final _PayoutGroup group;

  @override
  State<_PayoutCard> createState() => _PayoutCardState();
}

class _PayoutCardState extends State<_PayoutCard> {
  bool _busy = false;

  Future<void> _markPaid() async {
    final group = widget.group;
    final reference = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Paid ${formatPeso(group.amount)} to ${group.name}?'),
        content: TextField(
          controller: reference,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'GCash / Maya reference number',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              reference.text.trim().isNotEmpty,
            ),
            child: const Text('Mark as paid'),
          ),
        ],
      ),
    );
    final value = reference.text.trim();
    reference.dispose();
    if (confirmed != true || value.isEmpty) return;
    setState(() => _busy = true);
    try {
      await authService.database.markPayout(
        orderIds: group.orders.map((order) => order.id).toList(),
        payee: group.payee,
        reference: value,
      );
      widget.session.bump();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Payout to ${group.name} recorded.')),
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

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.name,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  Text(
                    '${plural(group.orders.length, 'order')} • '
                    '${group.number.isEmpty ? 'no payout number' : group.number}',
                    style: const TextStyle(color: muted, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formatPeso(group.amount),
                    style: const TextStyle(
                      color: green,
                      fontWeight: FontWeight.w700,
                      fontSize: 18, fontFamily: headingFont, fontFamilyFallback: headingFallback,
                    ),
                  ),
                ],
              ),
            ),
            FilledButton(
              onPressed: _busy || group.number.isEmpty ? null : _markPaid,
              child: const Text('Mark paid'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Every wallet entry on the network, with what buyers currently hold.
class WalletLedgerPage extends StatelessWidget {
  const WalletLedgerPage({super.key, required this.session});

  final AppSession session;

  static Future<
      ({
        List<WalletTransaction> entries,
        int pendingCashIns,
        Map<String, String> names,
      })> _load() async {
    final results = await Future.wait([
      authService.database.listAllWalletTransactions(),
      authService.database.listAllPendingCashIns(),
      authService.database.listAccounts(role: 'consumer'),
    ]);
    return (
      entries: results[0] as List<WalletTransaction>,
      pendingCashIns: (results[1] as List).length,
      names: {
        for (final account in results[2] as List<Map<String, dynamic>>)
          '${account['id']}': '${account['name']}',
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Buyer wallets')),
      body: LiveBuilder(
        session: session,
        load: _load,
        builder: (context, data) {
          final value = data.value;
          final entries = value?.entries ?? const <WalletTransaction>[];
          int total(WalletEntryType type) => entries
              .where((entry) => entry.type == type)
              .fold<int>(0, (sum, entry) => sum + entry.amount);
          final held = entries.fold<int>(0, (sum, entry) => sum + entry.amount);
          final names = value?.names ?? const <String, String>{};
          return LiveRefreshView(
            loading: data.loading,
            onRefresh: data.reload,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: MetricCard(
                        icon: Icons.savings_outlined,
                        value: formatPeso(held),
                        label: 'Held in wallets',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: MetricCard(
                        icon: Icons.hourglass_top,
                        value: '${value?.pendingCashIns ?? 0}',
                        label: 'Unpaid cash-ins',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: MetricCard(
                        icon: Icons.add_card,
                        value: formatPeso(total(WalletEntryType.cashIn)),
                        label: 'Cashed in',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: MetricCard(
                        icon: Icons.undo,
                        value: formatPeso(total(WalletEntryType.refund)),
                        label: 'Refunded',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                const SectionTitle(title: 'Latest entries', action: ''),
                const SizedBox(height: 10),
                if (data.error != null && value == null)
                  LiveErrorCard(
                    message: data.errorMessage,
                    onRetry: data.reload,
                  )
                else if (entries.isEmpty)
                  const EmptyState(
                    icon: Icons.account_balance_wallet_outlined,
                    title: 'No wallet activity yet',
                    message: 'Cash-ins, payments and refunds appear here.',
                  )
                else
                  for (final entry in entries.take(100))
                    Card(
                      child: ListTile(
                        title: Text(
                          names[entry.userId] ?? 'Buyer',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          '${entry.description.isEmpty ? entry.type.label : entry.description}'
                          '${entry.createdAt == null ? '' : '\n${formatRelativeDay(entry.createdAt!)} • ${formatClock(entry.createdAt!)}'}',
                        ),
                        trailing: Text(
                          '${entry.amount >= 0 ? '+' : ''}'
                          '${formatPeso(entry.amount)}',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: entry.amount >= 0 ? green : ink,
                          ),
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

/// Where the superadmin keeps delivery fees in step with the pump price.
class DeliveryRatesPage extends StatefulWidget {
  const DeliveryRatesPage({super.key, required this.session});

  final AppSession session;

  @override
  State<DeliveryRatesPage> createState() => _DeliveryRatesPageState();
}

class _DeliveryRatesPageState extends State<DeliveryRatesPage> {
  final _diesel = TextEditingController();
  final _kmPerLitre = TextEditingController();
  final _margin = TextEditingController();
  final _base = TextEditingController();
  final _handling = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    authService.database.loadDeliveryRates().then((rates) {
      if (!mounted) return;
      setState(() {
        _fill(rates);
        _loading = false;
      });
    });
  }

  void _fill(DeliveryRates rates) {
    String text(double value) => value == value.roundToDouble()
        ? '${value.round()}'
        : '$value';
    _diesel.text = text(rates.dieselPerLitre);
    _kmPerLitre.text = text(rates.kmPerLitre);
    _margin.text = text(rates.riderMarginPerKm);
    _base.text = text(rates.baseFare);
    _handling.text = text(rates.perKiloHandling);
  }

  DeliveryRates get _draft => DeliveryRates.fromMap({
        'dieselPerLitre': double.tryParse(_diesel.text.trim()),
        'kmPerLitre': double.tryParse(_kmPerLitre.text.trim()),
        'riderMarginPerKm': double.tryParse(_margin.text.trim()),
        'baseFare': double.tryParse(_base.text.trim()),
        'perKiloHandling': double.tryParse(_handling.text.trim()),
      });

  @override
  void dispose() {
    for (final controller in [_diesel, _kmPerLitre, _margin, _base, _handling]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await authService.database.saveDeliveryRates(_draft);
      widget.session.bump();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Delivery rates updated for new orders.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error'.replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(TextEditingController controller, String label,
          {String prefix = '', String suffix = ''}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: label,
            prefixText: prefix,
            suffixText: suffix,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final rates = _draft;
    return Scaffold(
      appBar: AppBar(title: const Text('Delivery pricing')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                const Text(
                  'Update the diesel price when it moves. The per-km rate is '
                  'set so the rider\'s share covers diesel both ways plus '
                  'their margin. Orders already placed keep the fee they '
                  'were quoted.',
                  style: TextStyle(color: muted, height: 1.4),
                ),
                const SizedBox(height: 18),
                _field(_diesel, 'Diesel price', prefix: '₱', suffix: '/L'),
                _field(_kmPerLitre, 'Van fuel economy', suffix: 'km/L'),
                _field(_margin, 'Rider margin', prefix: '₱', suffix: '/km'),
                _field(_base, 'Base fare per trip', prefix: '₱'),
                _field(_handling, 'Handling', prefix: '₱', suffix: '/kg'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        MoneyRow(
                          label: 'Diesel, there and back',
                          value: '${formatPeso(rates.roundTripFuelPerKm)}/km',
                        ),
                        MoneyRow(
                          label: 'Rider earns',
                          value: '${formatPeso(rates.riderPerKm)}/km',
                        ),
                        MoneyRow(
                          label: 'Buyer pays',
                          value: '${formatPeso(rates.perKilometre)}/km',
                          strong: true,
                        ),
                        const Divider(height: 22),
                        MoneyRow(
                          label: 'Example: 45 km, 100 kg',
                          value: formatPeso(
                            rates.fee(distanceKm: 45, quantityKg: 100),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: const Padding(
                    padding: EdgeInsets.all(14),
                    child: Text('Save rates'),
                  ),
                ),
              ],
            ),
    );
  }
}
