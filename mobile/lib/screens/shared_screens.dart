import 'dart:convert';

import 'package:flutter/material.dart';

import '../app.dart';
import '../models/agri_models.dart';
import '../models/mobile_user.dart';
import '../services/delivery_proof.dart';
import '../services/geo.dart';
import '../services/session.dart';
import '../utils/app_colors.dart';
import '../widgets/ui_kit.dart';
import 'auth_screens.dart';

/// Account editor shared by every role — the fields shown adapt to the role.
class ProfileEditorPage extends StatefulWidget {
  const ProfileEditorPage({super.key, required this.session});

  final AppSession session;

  @override
  State<ProfileEditorPage> createState() => _ProfileEditorPageState();
}

class _ProfileEditorPageState extends State<ProfileEditorPage> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _business;
  late final TextEditingController _vehicle;
  late final TextEditingController _payout;
  late Map<String, String> _profile;
  bool _saving = false;
  String? _error;

  MobileUser get _user => widget.session.user;

  @override
  void initState() {
    super.initState();
    _profile = Map<String, String>.from(_user.verification);
    _name = TextEditingController(text: _user.name);
    _phone = TextEditingController(text: _user.phone);
    _business = TextEditingController(
      text: _profile['establishmentName'] ?? _profile['farmName'] ?? '',
    );
    _vehicle = TextEditingController(text: _user.vehicle);
    _payout = TextEditingController(text: _user.payoutNumber);
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _business.dispose();
    _vehicle.dispose();
    _payout.dispose();
    super.dispose();
  }

  Future<void> _changeLocation() async {
    final result = await Navigator.push<LocationSelection>(
      context,
      MaterialPageRoute(builder: (_) => const LocationPickerPage()),
    );
    if (result == null || !mounted) return;
    setState(() {
      _profile['location'] = result.address;
      _profile['latitude'] = '${result.point.latitude}';
      _profile['longitude'] = '${result.point.longitude}';
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      switch (_user.role) {
        case MobileRole.consumer:
          _profile['establishmentName'] = _business.text.trim();
        case MobileRole.farmer:
          _profile['farmName'] = _business.text.trim();
          _profile['payoutNumber'] = _payout.text.trim();
        case MobileRole.rider:
          _profile['vehicle'] = _vehicle.text.trim();
          _profile['payoutNumber'] = _payout.text.trim();
        case MobileRole.superadmin:
          break;
      }
      await authService.database.updateDocument(
        'mobileUsers',
        _user.id,
        {
          'name': _name.text.trim(),
          'phone': _phone.text.trim(),
          'profile': _profile,
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
        },
      );
      widget.session.updateUser(
        _user.copyWith(
          name: _name.text.trim(),
          phone: _phone.text.trim(),
          verification: _profile,
        ),
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile changes saved to AgriLink.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error'.replaceFirst('Exception: ', '');
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = _user.role;
    return Scaffold(
      appBar: AppBar(title: const Text('Profile & Information')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const PageHeader(
            eyebrow: 'ACCOUNT SETTINGS',
            title: 'Your details',
            subtitle: 'Keep your account and operating details updated.',
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  const CircleAvatar(
                    radius: 36,
                    backgroundColor: lightGreen,
                    child: Icon(Icons.person, color: green, size: 38),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _name,
                    decoration: const InputDecoration(
                      labelText: 'Name / Representative',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Mobile number',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                  ),
                  if (role == MobileRole.consumer ||
                      role == MobileRole.farmer) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _business,
                      decoration: InputDecoration(
                        labelText: role == MobileRole.farmer
                            ? 'Farm name'
                            : 'Restaurant / Establishment',
                        prefixIcon: Icon(
                          role == MobileRole.farmer
                              ? Icons.agriculture
                              : Icons.storefront,
                        ),
                      ),
                    ),
                  ],
                  if (role == MobileRole.rider) ...[
                    const SizedBox(height: 12),
                    // Constrained to the same four-wheel list as signup, so a
                    // verified rider cannot quietly downgrade to a tricycle.
                    DropdownButtonFormField<String>(
                      initialValue: deliveryVehicles.contains(_vehicle.text)
                          ? _vehicle.text
                          : null,
                      isExpanded: true,
                      items: [
                        for (final vehicle in deliveryVehicles)
                          DropdownMenuItem(
                            value: vehicle,
                            child: Text(vehicle),
                          ),
                      ],
                      onChanged: (value) => _vehicle.text = value ?? '',
                      decoration: const InputDecoration(
                        labelText: 'Vehicle (4-wheel only)',
                        prefixIcon: Icon(Icons.local_shipping_outlined),
                      ),
                    ),
                  ],
                  if (role == MobileRole.rider ||
                      role == MobileRole.farmer) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _payout,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'GCash / Maya payout number',
                        prefixIcon:
                            Icon(Icons.account_balance_wallet_outlined),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading:
                        const Icon(Icons.location_on_outlined, color: green),
                    title: const Text(
                      'Pinned location',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      _profile['location']?.isNotEmpty == true
                          ? _profile['location']!
                          : 'Not set',
                    ),
                    trailing: const Icon(Icons.edit_location_alt_outlined),
                    onTap: _changeLocation,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      style: const TextStyle(
                        color: Color(0xFFB42318),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: const Icon(Icons.save_outlined),
                      label: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Text(_saving ? 'Saving…' : 'Save changes'),
                      ),
                    ),
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

Future<void> openProfileEditor(BuildContext context, AppSession session) =>
    Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => ProfileEditorPage(session: session)),
    );

/// Farm profile sheet opened from a crop listing.
Future<void> showFarmSheet(
  BuildContext context, {
  required AppSession session,
  required CropListing crop,
}) async {
  final farm = await authService.database.getAccount(crop.farmerId);
  if (!context.mounted) return;
  final profile = (farm?['profile'] as Map?) ?? const {};
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => Padding(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircleAvatar(
            radius: 30,
            backgroundColor: lightGreen,
            child: Icon(Icons.agriculture, color: green, size: 30),
          ),
          const SizedBox(height: 12),
          Text(
            '${farm?['name'] ?? crop.farmerName}',
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w700, fontFamily: headingFont, fontFamilyFallback: headingFallback,),
          ),
          const SizedBox(height: 5),
          Text(
            '${profile['location'] ?? crop.farmLocation}'.isEmpty
                ? 'Location unavailable'
                : '${profile['location'] ?? crop.farmLocation}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: muted),
          ),
          const SizedBox(height: 10),
          const Pill(
            icon: Icons.verified,
            text: 'VERIFIED FARM',
            color: green,
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(sheetContext);
              showReportSheet(
                context,
                session: session,
                targets: [
                  ReportTarget(
                    id: crop.farmerId,
                    name: crop.farmerName,
                    role: 'farmer',
                  ),
                ],
                cropId: crop.id,
              );
            },
            icon: const Icon(Icons.flag_outlined),
            label: const Text('Report this farmer'),
          ),
        ],
      ),
    ),
  );
}

/// "Same-day delivery", "Next-day delivery • Tue, Oct 12" or
/// "Scheduled • Mon, Oct 20", for order cards.
String deliveryScheduleLabel(AgriOrder order) {
  final date = order.deliveryDate;
  if (order.isScheduled && date != null) {
    return 'Scheduled \u2022 ${formatDeliveryDate(date)}';
  }
  if (order.isNextDay) {
    return 'Next-day delivery \u2022 ${formatDeliveryDate(date!)}';
  }
  return 'Same-day delivery';
}

/// Returns true once a report was actually filed.
/// Someone a report can be filed against.
class ReportTarget {
  const ReportTarget({
    required this.id,
    required this.name,
    required this.role,
  });

  final String id;
  final String name;

  /// `farmer`, `rider` or `consumer`, as stored on the account.
  final String role;

  String get roleLabel => switch (role) {
        'farmer' => 'Farm',
        'rider' => 'Rider',
        _ => 'Buyer',
      };
}

/// Sends a report to the superadmin, who can resolve it and suspend the
/// account it is filed against. With more than one [targets] the reporter
/// picks who the report is about; with none it is a general support report.
Future<bool> showReportSheet(
  BuildContext context, {
  required AppSession session,
  required List<ReportTarget> targets,
  String cropId = '',
  String orderId = '',
}) async {
  final people = [
    for (final target in targets)
      if (target.id.isNotEmpty) target,
  ];
  final reason = TextEditingController();
  var against = people.isEmpty ? null : people.first;
  final submit = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => AlertDialog(
        title: const Text('Report a problem'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (people.length > 1) ...[
                const Text(
                  'Who is this about?',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final person in people)
                      ChoiceChip(
                        label: Text('${person.roleLabel}: ${person.name}'),
                        selected: against == person,
                        onSelected: (_) => setState(() => against = person),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
              ] else if (people.length == 1) ...[
                Text(
                  'About ${people.first.roleLabel.toLowerCase()} '
                  '${people.first.name}',
                  style: const TextStyle(color: muted),
                ),
                const SizedBox(height: 10),
              ],
              TextField(
                controller: reason,
                maxLines: 3,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'What went wrong?',
                  hintText: switch (against?.role) {
                    'consumer' =>
                      'Fake payment, no-show, refused delivery, scam…',
                    'rider' => 'Late, rude, missing items, wrong drop-off…',
                    _ => 'Quantity mismatch, quality, late delivery…',
                  },
                ),
              ),
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
            child: const Text('Submit'),
          ),
        ],
      ),
    ),
  );
  final text = reason.text.trim();
  reason.dispose();
  if (submit != true || text.isEmpty) return false;
  ReportTarget? withRole(String role) =>
      people.where((person) => person.role == role).firstOrNull;
  final farm = withRole('farmer');
  final rider = withRole('rider');
  await authService.database.createReport({
    'reporterId': session.user.id,
    'reporterName': session.user.name,
    'reporterRole': session.user.role.name,
    if (against != null) ...{
      'againstId': against!.id,
      'againstName': against!.name,
      'againstRole': against!.role,
    },
    // Kept for the order context shown with the report.
    if (farm != null) 'farmerId': farm.id,
    if (farm != null) 'farmerName': farm.name,
    if (rider != null) 'riderId': rider.id,
    if (rider != null) 'riderName': rider.name,
    'cropId': cropId,
    'orderId': orderId,
    'reason': text,
  });
  session.bump();
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Report submitted to AgriLink support.')),
    );
  }
  return true;
}

/// The evidence a rider left at the drop-off: the photo, how far from the
/// buyer's pin it was taken, whether the buyer's code was entered, and when.
///
/// The photo never changes once stored, so it is fetched once rather than
/// polled with the order.
class DeliveryProofCard extends StatefulWidget {
  const DeliveryProofCard({super.key, required this.order});

  final AgriOrder order;

  @override
  State<DeliveryProofCard> createState() => _DeliveryProofCardState();
}

class _DeliveryProofCardState extends State<DeliveryProofCard> {
  late Future<Map<String, dynamic>?> _proof;

  @override
  void initState() {
    super.initState();
    _proof = _load();
  }

  @override
  void didUpdateWidget(DeliveryProofCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.order.deliveryProofId != widget.order.deliveryProofId) {
      _proof = _load();
    }
  }

  Future<Map<String, dynamic>?> _load() =>
      authService.database.getDeliveryProof(widget.order.deliveryProofId);

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final distance = order.deliveredDistanceMetres;
    final at = order.timeline[OrderStatus.delivered.wire];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Proof of delivery',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            if (order.deliveryProofId.isEmpty)
              const Text(
                'This order was delivered before photo proof was required.',
                style: TextStyle(color: muted, height: 1.4),
              )
            else
              FutureBuilder<Map<String, dynamic>?>(
                future: _proof,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const SizedBox(
                      height: 160,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final photo = '${snapshot.data?['photoBase64'] ?? ''}';
                  if (photo.isEmpty) {
                    return const Text(
                      'The delivery photo could not be loaded.',
                      style: TextStyle(color: muted),
                    );
                  }
                  final bytes = base64Decode(photo);
                  return GestureDetector(
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (_) => Dialog(
                        child: InteractiveViewer(child: Image.memory(bytes)),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(
                        bytes,
                        height: 200,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                  );
                },
              ),
            const SizedBox(height: 12),
            if (order.deliveredOutsidePin)
              _ProofLine(
                icon: Icons.wrong_location_outlined,
                color: orange,
                text: distance == null
                    ? 'Confirmed without a GPS fix after GPS kept failing'
                    : 'Confirmed ${DeliveryProof.formatMetres(distance)} from '
                        'the delivery pin after GPS kept failing',
              )
            else
              _ProofLine(
                icon: Icons.where_to_vote_outlined,
                text: distance == null
                    ? 'No pinned location to measure against'
                    : 'Confirmed ${DeliveryProof.formatMetres(distance)} '
                        'from the delivery pin',
              ),
            _ProofLine(
              icon: order.deliveryCodeVerified
                  ? Icons.verified_user_outlined
                  : Icons.remove_moderator_outlined,
              text: order.deliveryCodeVerified
                  ? 'Buyer\'s delivery code entered by the rider'
                  : 'No delivery code on this order',
            ),
            if (at != null)
              _ProofLine(
                icon: Icons.schedule,
                text: 'Delivered ${formatRelativeDay(at)} • ${formatClock(at)}',
              ),
            if (order.isReceiptConfirmed)
              _ProofLine(
                icon: Icons.thumb_up_alt_outlined,
                text: 'Buyer confirmed receipt '
                    '${formatRelativeDay(order.receivedConfirmedAt!)} • '
                    '${formatClock(order.receivedConfirmedAt!)}',
              ),
            if (order.isDisputed)
              const _ProofLine(
                icon: Icons.report_outlined,
                text: 'Buyer reported a problem with this delivery',
                color: orange,
              ),
          ],
        ),
      ),
    );
  }
}

/// The photo the rider took when collecting at the farm, with where it was
/// taken, for the farm's order details.
class PickupProofCard extends StatelessWidget {
  const PickupProofCard({super.key, required this.order});

  final AgriOrder order;

  @override
  Widget build(BuildContext context) {
    final distance = order.pickupDistanceMetres;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Proof of pickup',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            FutureBuilder<Map<String, dynamic>?>(
              future:
                  authService.database.getDeliveryProof(order.pickupProofId),
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const SizedBox(
                    height: 160,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final photo = '${snapshot.data?['photoBase64'] ?? ''}';
                if (photo.isEmpty) {
                  return const Text(
                    'The pickup photo could not be loaded.',
                    style: TextStyle(color: muted),
                  );
                }
                return ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    base64Decode(photo),
                    height: 200,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                );
              },
            ),
            const SizedBox(height: 6),
            _ProofLine(
              icon: order.pickupOutsidePin
                  ? Icons.wrong_location_outlined
                  : Icons.where_to_vote_outlined,
              color: order.pickupOutsidePin ? orange : green,
              text: distance == null
                  ? order.pickupOutsidePin
                      ? 'Collected without a GPS fix after GPS kept failing'
                      : 'No farm pin to measure against'
                  : 'Collected ${DeliveryProof.formatMetres(distance)} from '
                      'the farm pin'
                      '${order.pickupOutsidePin ? ' after GPS kept failing' : ''}',
            ),
          ],
        ),
      ),
    );
  }
}

class _ProofLine extends StatelessWidget {
  const _ProofLine({required this.icon, required this.text, this.color = green});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: const TextStyle(height: 1.35)),
          ),
        ],
      ),
    );
  }
}
