import 'package:flutter/material.dart';

import '../app.dart';
import '../models/agri_models.dart';
import '../models/mobile_user.dart';
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
                    TextField(
                      controller: _vehicle,
                      decoration: const InputDecoration(
                        labelText: 'Vehicle',
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
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
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
                farmerId: crop.farmerId,
                farmerName: crop.farmerName,
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

/// Sends a dispute to the superadmin queue.
Future<void> showReportSheet(
  BuildContext context, {
  required AppSession session,
  required String farmerId,
  required String farmerName,
  String cropId = '',
  String orderId = '',
}) async {
  final reason = TextEditingController();
  final submit = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Report a problem'),
      content: TextField(
        controller: reason,
        maxLines: 3,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'What went wrong?',
          hintText: 'Quantity mismatch, quality, late delivery…',
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
  );
  if (submit != true || reason.text.trim().isEmpty) return;
  await authService.database.createReport({
    'reporterId': session.user.id,
    'reporterName': session.user.name,
    'reporterRole': session.user.role.name,
    'farmerId': farmerId,
    'farmerName': farmerName,
    'cropId': cropId,
    'orderId': orderId,
    'reason': reason.text.trim(),
  });
  session.bump();
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Report submitted to AgriLink support.')),
  );
}
