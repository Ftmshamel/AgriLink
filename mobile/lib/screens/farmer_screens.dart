import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app.dart';
import '../models/agri_models.dart';
import '../services/geo.dart';
import '../services/session.dart';
import '../utils/app_colors.dart';
import '../widgets/live_data.dart';
import '../widgets/ui_kit.dart';
import 'shared_screens.dart';

class FarmerShell extends StatefulWidget {
  const FarmerShell({super.key, required this.session});
  final AppSession session;

  @override
  State<FarmerShell> createState() => _FarmerShellState();
}

class _FarmerShellState extends State<FarmerShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      FarmerDashboard(
        session: widget.session,
        onOpenOrders: () => setState(() => _index = 2),
        onOpenCrops: () => setState(() => _index = 1),
      ),
      FarmerInventory(session: widget.session),
      FarmerFulfillment(session: widget.session),
      FarmerProfile(session: widget.session),
    ];
    return Scaffold(
      body: SafeArea(child: LiveIndexedStack(index: _index, children: pages)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'Crops',
          ),
          NavigationDestination(
            icon: Icon(Icons.local_shipping_outlined),
            selectedIcon: Icon(Icons.local_shipping),
            label: 'Orders',
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

/// Everything the dashboard, inventory, and fulfilment tabs need in one load.
class FarmerSnapshot {
  const FarmerSnapshot({required this.crops, required this.orders});

  final List<CropListing> crops;
  final List<AgriOrder> orders;

  int get activeCrops => crops.where((crop) => crop.inStock).length;
  int get stockKg =>
      crops.fold<int>(0, (total, crop) => total + crop.quantityKg);
  List<AgriOrder> get newOrders =>
      orders.where((order) => order.status == OrderStatus.placed).toList();
  List<AgriOrder> get packing =>
      orders.where((order) => order.status == OrderStatus.preparing).toList();
  List<AgriOrder> get awaitingRider => orders
      .where((order) => order.status == OrderStatus.readyForPickup)
      .toList();
  List<AgriOrder> get inTransit =>
      orders.where((order) => order.status.isWithRider).toList();

  /// Produce revenue from orders delivered in the last seven days.
  int get weekEarnings {
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    return orders
        .where((order) =>
            order.status == OrderStatus.delivered &&
            (order.timeline[OrderStatus.delivered.wire] ??
                    order.createdAt ??
                    DateTime(1970))
                .isAfter(cutoff))
        .fold<int>(0, (total, order) => total + order.totalPrice);
  }

  static Future<FarmerSnapshot> load(String farmerId) async {
    final results = await Future.wait([
      authService.database.listCropListings(farmerId: farmerId),
      authService.database.listAgriOrders(farmerId: farmerId),
    ]);
    return FarmerSnapshot(
      crops: results[0] as List<CropListing>,
      orders: results[1] as List<AgriOrder>,
    );
  }
}

class FarmerDashboard extends StatelessWidget {
  const FarmerDashboard({
    super.key,
    required this.session,
    required this.onOpenOrders,
    required this.onOpenCrops,
  });

  final AppSession session;
  final VoidCallback onOpenOrders;
  final VoidCallback onOpenCrops;

  @override
  Widget build(BuildContext context) {
    return LiveBuilder<FarmerSnapshot>(
      session: session,
      load: () => FarmerSnapshot.load(session.user.id),
      builder: (context, data) {
        final snapshot =
            data.value ?? const FarmerSnapshot(crops: [], orders: []);
        final attention = [...snapshot.newOrders, ...snapshot.packing];
        return LiveRefreshView(
          loading: data.loading,
          onRefresh: data.reload,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              PageHeader(
                eyebrow: 'FARMER DASHBOARD',
                title: 'Good day, ${session.user.name}',
                subtitle: 'Manage today’s harvest and incoming bulk orders.',
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: MetricCard(
                      icon: Icons.grass,
                      value: '${snapshot.activeCrops}',
                      label: 'Active crops',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: MetricCard(
                      icon: Icons.shopping_bag_outlined,
                      value: '${snapshot.newOrders.length}',
                      label: 'New orders',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: MetricCard(
                      icon: Icons.inventory,
                      value: '${snapshot.stockKg} kg',
                      label: 'Available stock',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: MetricCard(
                      icon: Icons.payments_outlined,
                      value: formatPeso(snapshot.weekEarnings),
                      label: 'This week',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SectionTitle(
                title: 'Incoming orders',
                action: 'View all',
                onAction: onOpenOrders,
              ),
              const SizedBox(height: 10),
              if (data.error != null && !data.hasValue)
                LiveErrorCard(message: data.errorMessage, onRetry: data.reload)
              else if (attention.isEmpty)
                const EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'No orders waiting',
                  message: 'New consumer bookings will appear here.',
                )
              else
                for (final order in attention.take(4)) ...[
                  ActionCard(
                    icon: Icons.restaurant,
                    title: '${order.buyerName} • ${order.quantityKg} kg',
                    subtitle:
                        '${order.cropName} • ${formatPeso(order.totalPrice)}',
                    badge: order.status == OrderStatus.placed
                        ? 'NEW'
                        : 'PACKING',
                  ),
                  const SizedBox(height: 10),
                ],
              const SizedBox(height: 14),
              SectionTitle(
                title: 'Harvest catalog',
                action: 'Manage',
                onAction: onOpenCrops,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: MetricCard(
                      icon: Icons.local_shipping_outlined,
                      value: '${snapshot.awaitingRider.length}',
                      label: 'Waiting for rider',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: MetricCard(
                      icon: Icons.route,
                      value: '${snapshot.inTransit.length}',
                      label: 'On the road',
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class FarmerInventory extends StatelessWidget {
  const FarmerInventory({super.key, required this.session});

  final AppSession session;

  @override
  Widget build(BuildContext context) {
    return LiveBuilder<List<CropListing>>(
      session: session,
      load: () =>
          authService.database.listCropListings(farmerId: session.user.id),
      builder: (context, data) {
        final crops = data.value ?? const <CropListing>[];
        return LiveRefreshView(
          loading: data.loading,
          onRefresh: data.reload,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const PageHeader(
                eyebrow: 'HARVEST CATALOG',
                title: 'Crops & Stock',
                subtitle: 'Update prices and available harvest quantities.',
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _openEditor(context, null),
                icon: const Icon(Icons.add),
                label: const Text('List a new harvest'),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7E8),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: const Color(0xFFFFD99A)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.insights_outlined, color: orange),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        crops.isEmpty
                            ? 'Buyers can only book harvests that are listed here.'
                            : 'Your listings are live in the market. Keep stock accurate so buyers see what you really have.',
                        style: const TextStyle(fontSize: 12, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (data.error != null && crops.isEmpty)
                LiveErrorCard(message: data.errorMessage, onRetry: data.reload)
              else if (crops.isEmpty)
                const EmptyState(
                  icon: Icons.add_business_outlined,
                  title: 'No crop listings',
                  message: 'Tap “List a new harvest” to publish your first crop.',
                )
              else
                for (final crop in crops) ...[
                  Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(12),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          width: 52,
                          height: 52,
                          child: crop.photoBase64 != null &&
                                  crop.photoBase64!.isNotEmpty
                              ? Image.memory(
                                  base64Decode(crop.photoBase64!),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      _emojiBox(crop),
                                )
                              : _emojiBox(crop),
                        ),
                      ),
                      title: Text(
                        crop.name,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      subtitle: Text(
                        '${crop.quantityKg} kg • ₱${crop.pricePerKg}/kg\n'
                        'MOQ ${crop.moqKg} kg${crop.harvestDate.isEmpty ? '' : ' • Harvest ${crop.harvestDate}'}',
                      ),
                      isThreeLine: true,
                      trailing: IconButton(
                        icon: const Icon(Icons.edit_outlined, color: green),
                        onPressed: () => _openEditor(context, crop),
                      ),
                      onTap: () => _openEditor(context, crop),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
            ],
          ),
        );
      },
    );
  }

  Widget _emojiBox(CropListing crop) => Container(
        color: lightGreen,
        alignment: Alignment.center,
        child: Text(crop.emoji, style: const TextStyle(fontSize: 24)),
      );

  Future<void> _openEditor(BuildContext context, CropListing? crop) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CropEditorPage(session: session, crop: crop),
      ),
    );
    if (saved == true) session.bump();
  }
}

/// Create/edit form for a harvest listing.
class CropEditorPage extends StatefulWidget {
  const CropEditorPage({super.key, required this.session, this.crop});

  final AppSession session;
  final CropListing? crop;

  @override
  State<CropEditorPage> createState() => _CropEditorPageState();
}

class _CropEditorPageState extends State<CropEditorPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name =
      TextEditingController(text: widget.crop?.name ?? '');
  late final TextEditingController _quantity = TextEditingController(
    text: widget.crop == null ? '' : '${widget.crop!.quantityKg}',
  );
  late final TextEditingController _price = TextEditingController(
    text: widget.crop == null ? '' : '${widget.crop!.pricePerKg}',
  );
  late final TextEditingController _moq = TextEditingController(
    text: widget.crop == null ? '10' : '${widget.crop!.moqKg}',
  );
  late CropCategory _category = widget.crop?.category ?? CropCategory.vegetables;
  late DateTime _harvest = DateTime.tryParse(widget.crop?.harvestDate ?? '') ??
      DateTime.now().add(const Duration(days: 3));

  Uint8List? _photoBytes;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.crop != null;

  @override
  void dispose() {
    _name.dispose();
    _quantity.dispose();
    _price.dispose();
    _moq.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 50,
      maxWidth: 1200,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    if (bytes.length > 700000) {
      setState(() => _error = 'Choose a crop photo below 700 KB.');
      return;
    }
    setState(() {
      _photoBytes = bytes;
      _error = null;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final user = widget.session.user;
    if (!_isEdit && _photoBytes == null) {
      setState(() => _error = 'Add a photo of the harvest.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final fields = <String, dynamic>{
        'name': _name.text.trim(),
        'category': _category.label,
        'quantityKg': int.parse(_quantity.text.trim()),
        'pricePerKg': int.parse(_price.text.trim()),
        'moqKg': int.parse(_moq.text.trim()),
        'harvestDate': _harvest.toIso8601String().split('T').first,
        'status': 'active',
        if (_photoBytes != null) 'photoBase64': base64Encode(_photoBytes!),
      };
      if (_isEdit) {
        // Re-stamp the contact details so an edited listing picks up any
        // profile changes the farmer made since publishing.
        await authService.database.updateCrop(widget.crop!.id, {
          ...fields,
          'farmerName': user.businessName,
          'farmerPhone': user.phone,
          'farmLocation': user.location,
          'farmLatitude': user.latitude,
          'farmLongitude': user.longitude,
        });
      } else {
        await authService.database.createCrop({
          ...fields,
          'farmerId': user.id,
          'farmerName': user.businessName,
          'farmerPhone': user.phone,
          'farmLocation': user.location,
          'farmLatitude': user.latitude,
          'farmLongitude': user.longitude,
        });
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error'.replaceFirst('Exception: ', '');
        _saving = false;
      });
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove listing?'),
        content: Text(
          '${widget.crop!.name} will no longer be visible to buyers. '
          'Existing orders are not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await authService.database.deleteCrop(widget.crop!.id);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.session.user;
    final existingPhoto = widget.crop?.photoBase64;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit listing' : 'List a harvest'),
        actions: [
          if (_isEdit)
            IconButton(
              tooltip: 'Remove listing',
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            InkWell(
              onTap: _pickPhoto,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                height: 190,
                decoration: BoxDecoration(
                  color: lightGreen,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFD7E7CB)),
                ),
                clipBehavior: Clip.antiAlias,
                child: _photoBytes != null
                    ? Image.memory(
                        _photoBytes!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                      )
                    : existingPhoto != null && existingPhoto.isNotEmpty
                        ? Image.memory(
                            base64Decode(existingPhoto),
                            fit: BoxFit.cover,
                            width: double.infinity,
                          )
                        : const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_a_photo_outlined,
                                  color: green, size: 34),
                              SizedBox(height: 10),
                              Text(
                                'Add a harvest photo',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: darkGreen,
                                ),
                              ),
                            ],
                          ),
              ),
            ),
            const SizedBox(height: 18),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Crop name',
                hintText: 'e.g. Red onions',
                prefixIcon: Icon(Icons.eco_outlined),
              ),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? 'Enter a crop name.' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<CropCategory>(
              initialValue: _category,
              decoration: const InputDecoration(
                labelText: 'Category',
                prefixIcon: Icon(Icons.category_outlined),
              ),
              items: CropCategory.values
                  .map(
                    (category) => DropdownMenuItem(
                      value: category,
                      child: Text('${category.emoji}  ${category.label}'),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(
                () => _category = value ?? CropCategory.vegetables,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _quantity,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Available kg',
                      prefixIcon: Icon(Icons.scale_outlined),
                    ),
                    validator: _positive,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _price,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Price / kg',
                      prefixText: '₱',
                    ),
                    validator: _positive,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _moq,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Minimum order (kg)',
                prefixIcon: Icon(Icons.shopping_basket_outlined),
              ),
              validator: _positive,
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.calendar_month, color: green),
                title: const Text(
                  'Harvest date',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(_harvest.toIso8601String().split('T').first),
                trailing: const Icon(Icons.edit_calendar_outlined),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    firstDate:
                        DateTime.now().subtract(const Duration(days: 30)),
                    lastDate: DateTime.now().add(const Duration(days: 730)),
                    initialDate: _harvest,
                  );
                  if (picked != null) setState(() => _harvest = picked);
                },
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.location_on_outlined, color: green),
                title: const Text(
                  'Farm location',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  user.location.isEmpty
                      ? 'Pin your farm in Profile so riders can find you'
                      : user.location,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => openProfileEditor(context, widget.session),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(
                  color: Color(0xFFB42318),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(padding: const EdgeInsets.all(16)),
              child: Text(
                _saving
                    ? 'Saving…'
                    : _isEdit
                        ? 'Save changes'
                        : 'Publish to market',
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _positive(String? value) {
    final parsed = int.tryParse((value ?? '').trim());
    if (parsed == null || parsed <= 0) return 'Enter a number above 0.';
    return null;
  }
}

class FarmerFulfillment extends StatelessWidget {
  const FarmerFulfillment({super.key, required this.session});

  final AppSession session;

  @override
  Widget build(BuildContext context) {
    return LiveBuilder<List<AgriOrder>>(
      session: session,
      load: () =>
          authService.database.listAgriOrders(farmerId: session.user.id),
      builder: (context, data) {
        final orders = data.value ?? const <AgriOrder>[];
        final open = orders.where((order) => order.status.isOpen).toList();
        final done = orders.where((order) => !order.status.isOpen).toList();
        return LiveRefreshView(
          loading: data.loading,
          onRefresh: data.reload,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const PageHeader(
                eyebrow: 'ORDER FULFILLMENT',
                title: 'Prepare & Dispatch',
                subtitle:
                    'Pack confirmed orders and send them to the rider pool.',
              ),
              const SizedBox(height: 18),
              if (data.error != null && orders.isEmpty)
                LiveErrorCard(message: data.errorMessage, onRetry: data.reload)
              else if (open.isEmpty && done.isEmpty)
                const EmptyState(
                  icon: Icons.local_shipping_outlined,
                  title: 'No orders yet',
                  message:
                      'When a buyer books one of your harvests it lands here.',
                ),
              for (final order in open) ...[
                FulfillmentCard(session: session, order: order),
                const SizedBox(height: 12),
              ],
              if (done.isNotEmpty) ...[
                const SizedBox(height: 8),
                const SectionTitle(title: 'Completed', action: ''),
                const SizedBox(height: 10),
                for (final order in done) ...[
                  PastOrderCard(
                    id: order.reference,
                    emoji: order.emoji,
                    name: order.cropName,
                    detail: '${order.quantityKg} kg • ${order.buyerName}',
                    price: formatPeso(order.totalPrice),
                    statusText: order.status == OrderStatus.delivered
                        ? 'DELIVERED'
                        : 'CANCELLED',
                    statusIcon: order.status == OrderStatus.delivered
                        ? Icons.check_circle
                        : Icons.cancel,
                    statusColor:
                        order.status == OrderStatus.delivered ? green : muted,
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ],
          ),
        );
      },
    );
  }
}

/// One order the farmer still has work to do on.
class FulfillmentCard extends StatefulWidget {
  const FulfillmentCard({
    super.key,
    required this.session,
    required this.order,
  });

  final AppSession session;
  final AgriOrder order;

  @override
  State<FulfillmentCard> createState() => _FulfillmentCardState();
}

class _FulfillmentCardState extends State<FulfillmentCard> {
  bool _busy = false;

  Future<void> _advance(OrderStatus next) async {
    setState(() => _busy = true);
    try {
      await authService.database.advanceOrder(
        widget.order.id,
        next,
        existingTimeline: widget.order.timeline,
      );
      widget.session.bump();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            next == OrderStatus.readyForPickup
                ? 'Order pushed to the rider pool.'
                : 'Order confirmed. Time to pack it.',
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

  Future<void> _cancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel this order?'),
        content: const Text(
          'The buyer will see it as cancelled. Do this only if you cannot '
          'supply the harvest.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep order'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Cancel order'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _advance(OrderStatus.cancelled);
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${order.reference} • ${order.buyerName}',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                Text(
                  formatPeso(order.totalPrice),
                  style: const TextStyle(
                    color: green,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${order.cropName} • ${order.quantityKg} kg • ${order.status.label}',
              style: const TextStyle(color: muted),
            ),
            const SizedBox(height: 6),
            Text(
              order.deliveryAddress.isEmpty
                  ? 'No delivery address on file'
                  : order.deliveryAddress,
              style: const TextStyle(color: muted, fontSize: 12, height: 1.4),
            ),
            if (order.status == OrderStatus.readyForPickup) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: canvas,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.inventory_2_outlined, color: green, size: 19),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Waiting for a rider to accept this pickup',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (order.hasRider) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const CircleAvatar(
                    radius: 16,
                    backgroundColor: Color(0xFFFFF1DD),
                    child: Icon(Icons.two_wheeler, color: orange, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${order.riderName}${order.riderVehicle.isEmpty ? '' : ' • ${order.riderVehicle}'}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (order.riderPhone.isNotEmpty)
                    IconButton.filledTonal(
                      tooltip: 'Call rider',
                      onPressed: () => launchUrl(
                        Uri(scheme: 'tel', path: order.riderPhone),
                      ),
                      icon: const Icon(Icons.call, size: 18),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            if (order.status == OrderStatus.placed)
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _advance(OrderStatus.preparing),
                      icon: const Icon(Icons.check),
                      label: const Text('Confirm order'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    tooltip: 'Cancel order',
                    onPressed: _busy ? null : _cancel,
                    icon: const Icon(Icons.close),
                  ),
                ],
              )
            else if (order.status == OrderStatus.preparing)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _advance(OrderStatus.readyForPickup),
                  icon: const Icon(Icons.send_outlined),
                  label: const Text('Packed — push to rider pool'),
                ),
              )
            else
              Row(
                children: [
                  Pill(
                    icon: Icons.local_shipping,
                    text: order.status.label.toUpperCase(),
                    color: green,
                  ),
                  const Spacer(),
                  if (order.riderUpdatedAt != null)
                    Text(
                      'Updated ${formatClock(order.riderUpdatedAt!)}',
                      style: const TextStyle(color: muted, fontSize: 11),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class FarmerProfile extends StatelessWidget {
  const FarmerProfile({super.key, required this.session});

  final AppSession session;

  @override
  Widget build(BuildContext context) {
    final user = session.user;
    return LiveBuilder<FarmerSnapshot>(
      session: session,
      load: () => FarmerSnapshot.load(user.id),
      builder: (context, data) {
        final snapshot =
            data.value ?? const FarmerSnapshot(crops: [], orders: []);
        final delivered = snapshot.orders
            .where((order) => order.status == OrderStatus.delivered)
            .toList();
        final revenue =
            delivered.fold<int>(0, (sum, order) => sum + order.totalPrice);
        return LiveRefreshView(
          loading: data.loading,
          onRefresh: data.reload,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              PageHeader(
                eyebrow: 'FARMER ACCOUNT',
                title: user.businessName,
                subtitle: '${user.email} • ${user.phone}',
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: StatCard(
                      icon: Icons.payments_outlined,
                      label: 'Lifetime sales',
                      value: formatPeso(revenue),
                      tint: lightGreen,
                      color: green,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatCard(
                      icon: Icons.check_circle_outline,
                      label: 'Delivered',
                      value: '${delivered.length}',
                      tint: const Color(0xFFFFF1DD),
                      color: orange,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ProfileTile(
                icon: Icons.location_on_outlined,
                title: 'Farm location',
                subtitle:
                    user.location.isEmpty ? 'Not pinned yet' : user.location,
                onTap: () => openProfileEditor(context, session),
              ),
              ProfileTile(
                icon: Icons.account_balance_wallet_outlined,
                title: 'Payout number',
                subtitle: user.payoutNumber.isEmpty
                    ? 'Add your GCash / Maya number'
                    : user.payoutNumber,
                onTap: () => openProfileEditor(context, session),
              ),
              ProfileTile(
                icon: Icons.eco_outlined,
                title: 'Listings',
                subtitle:
                    '${snapshot.crops.length} crop${snapshot.crops.length == 1 ? '' : 's'} published',
                onTap: () {},
              ),
              ProfileTile(
                icon: Icons.verified_user_outlined,
                title: 'Verification',
                subtitle: user.isApproved
                    ? 'Approved by AgriLink'
                    : 'Under review',
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
}
