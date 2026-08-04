import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app.dart';
import '../models/agri_models.dart';
import '../services/geo.dart';
import '../services/session.dart';
import '../utils/app_colors.dart';
import '../widgets/live_data.dart';
import '../widgets/live_map.dart';
import '../widgets/ui_kit.dart';
import 'shared_screens.dart';

/// Background tint behind a crop tile, matching the original mockup palette.
Color cropTint(CropCategory category) => switch (category) {
      CropCategory.leafy => const Color(0xFFE4F3DB),
      CropCategory.vegetables => const Color(0xFFFFE7E2),
      CropCategory.fruits => const Color(0xFFFFF1C7),
      CropCategory.grains => const Color(0xFFF3E3ED),
    };

class ConsumerShell extends StatefulWidget {
  const ConsumerShell({super.key, required this.session});
  final AppSession session;

  @override
  State<ConsumerShell> createState() => _ConsumerShellState();
}

class _ConsumerShellState extends State<ConsumerShell> {
  final _cart = CartController();
  int _index = 0;

  @override
  void dispose() {
    _cart.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      ConsumerHome(
        session: widget.session,
        cart: _cart,
        onOpenCart: _openCart,
      ),
      ConsumerOrders(session: widget.session),
      ConsumerProfile(session: widget.session),
    ];
    return Scaffold(
      body: SafeArea(child: LiveIndexedStack(index: _index, children: pages)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront),
            label: 'Market',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
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

  Future<void> _openCart() async {
    final placed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => CartSheet(session: widget.session, cart: _cart),
    );
    if (placed == true && mounted) setState(() => _index = 1);
  }
}

class ConsumerHome extends StatefulWidget {
  const ConsumerHome({
    super.key,
    required this.session,
    required this.cart,
    required this.onOpenCart,
  });

  final AppSession session;
  final CartController cart;
  final VoidCallback onOpenCart;

  @override
  State<ConsumerHome> createState() => _ConsumerHomeState();
}

class _ConsumerHomeState extends State<ConsumerHome> {
  final _search = TextEditingController();
  CropCategory? _category;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning,';
    if (hour < 18) return 'Good afternoon,';
    return 'Good evening,';
  }

  List<CropListing> _visible(List<CropListing> crops) {
    final query = _search.text.trim().toLowerCase();
    final buyerPoint = widget.session.user.point;
    final filtered = crops.where((crop) {
      if (!crop.inStock) return false;
      if (_category != null && crop.category != _category) return false;
      if (query.isEmpty) return true;
      return '${crop.name} ${crop.farmerName} ${crop.farmLocation}'
          .toLowerCase()
          .contains(query);
    }).toList();
    filtered.sort((a, b) {
      final left = a.distanceKmFrom(buyerPoint);
      final right = b.distanceKmFrom(buyerPoint);
      if (left == null && right == null) return 0;
      if (left == null) return 1;
      if (right == null) return -1;
      return left.compareTo(right);
    });
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.session.user;
    return LiveBuilder<List<CropListing>>(
      session: widget.session,
      load: () => authService.database.listCropListings(),
      builder: (context, data) {
        final crops = _visible(data.value ?? const []);
        return LiveRefreshView(
          loading: data.loading,
          onRefresh: data.reload,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_greeting, style: const TextStyle(color: muted)),
                        Text(
                          user.name,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ListenableBuilder(
                    listenable: widget.cart,
                    builder: (context, _) => Badge(
                      isLabelVisible: widget.cart.count > 0,
                      label: Text('${widget.cart.count}'),
                      child: IconButton.filledTonal(
                        onPressed: widget.onOpenCart,
                        icon: const Icon(Icons.shopping_cart_outlined),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search crops or farms',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _search.text.isEmpty
                      ? const Icon(Icons.tune)
                      : IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _search.clear();
                            setState(() {});
                          },
                        ),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [darkGreen, green]),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'FARM-TO-TABLE',
                            style: TextStyle(
                              color: Color(0xFFBDE7A9),
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.3,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Save more when\nyou buy in bulk.',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 23,
                              fontWeight: FontWeight.w900,
                              height: 1.15,
                            ),
                          ),
                          SizedBox(height: 10),
                          Text(
                            'Direct prices from verified farms',
                            style: TextStyle(color: Color(0xFFD8EAD1)),
                          ),
                        ],
                      ),
                    ),
                    Text('🧺', style: TextStyle(fontSize: 66)),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SectionTitle(
                title: 'Browse categories',
                action: _category == null ? 'See all' : 'Clear',
                onAction: () => setState(() => _category = null),
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final category in CropCategory.values)
                      CategoryChip(
                        emoji: category.emoji,
                        label: category.label,
                        selected: _category == category,
                        onTap: () => setState(
                          () => _category =
                              _category == category ? null : category,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 26),
              SectionTitle(
                title: 'Fresh near you',
                action: 'View map',
                onAction: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FarmMapPage(
                      crops: crops,
                      origin: user.point,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (data.error != null && (data.value ?? const []).isEmpty)
                LiveErrorCard(
                  message: data.errorMessage,
                  onRetry: data.reload,
                )
              else if (crops.isEmpty)
                EmptyState(
                  icon: Icons.eco_outlined,
                  title: _search.text.isEmpty && _category == null
                      ? 'No harvests listed yet'
                      : 'No matching harvests',
                  message: _search.text.isEmpty && _category == null
                      ? 'Verified farmers will publish their crops here.'
                      : 'Try another crop name, farm, or category.',
                )
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: .66,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: crops.length,
                  itemBuilder: (context, index) {
                    final crop = crops[index];
                    return CropTile(
                      crop: crop,
                      distanceKm: crop.distanceKmFrom(user.point),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ProductDetails(
                            session: widget.session,
                            crop: crop,
                            cart: widget.cart,
                            onOpenCart: widget.onOpenCart,
                          ),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Market grid tile. Shows the farmer's photo when there is one and falls back
/// to the mockup's tinted emoji tile otherwise.
class CropTile extends StatelessWidget {
  const CropTile({
    super.key,
    required this.crop,
    required this.onTap,
    this.distanceKm,
  });

  final CropListing crop;
  final VoidCallback onTap;
  final double? distanceKm;

  @override
  Widget build(BuildContext context) {
    final photo = crop.photoBase64;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: photo != null && photo.isNotEmpty
                  ? Image.memory(
                      base64Decode(photo),
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _emojiTile(),
                    )
                  : _emojiTile(),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    crop.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '₱${crop.pricePerKg}/kg',
                    style: const TextStyle(
                      color: green,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      const Icon(Icons.location_on, color: muted, size: 13),
                      Expanded(
                        child: Text(
                          ' ${distanceKm != null ? formatKm(distanceKm!) : crop.farmLocation}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: muted, fontSize: 11),
                        ),
                      ),
                      const Icon(Icons.verified, color: green, size: 14),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emojiTile() => Container(
        width: double.infinity,
        color: cropTint(crop.category),
        alignment: Alignment.center,
        child: Text(crop.emoji, style: const TextStyle(fontSize: 62)),
      );
}

class ProductDetails extends StatefulWidget {
  const ProductDetails({
    super.key,
    required this.session,
    required this.crop,
    required this.cart,
    required this.onOpenCart,
  });

  final AppSession session;
  final CropListing crop;
  final CartController cart;
  final VoidCallback onOpenCart;

  @override
  State<ProductDetails> createState() => _ProductDetailsState();
}

class _ProductDetailsState extends State<ProductDetails> {
  late int quantity = widget.crop.moqKg;

  int get _step => widget.crop.moqKg > 0 ? widget.crop.moqKg : 1;

  /// A listing whose remaining stock is under its own minimum order cannot be
  /// bought without overselling the farm.
  bool get _canOrder => widget.crop.quantityKg >= widget.crop.moqKg;

  @override
  Widget build(BuildContext context) {
    final crop = widget.crop;
    final total = crop.pricePerKg * quantity;
    final photo = crop.photoBase64;
    final distance = crop.distanceKmFrom(widget.session.user.point);
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Report this listing',
            onPressed: () => showReportSheet(
              context,
              session: widget.session,
              farmerId: crop.farmerId,
              farmerName: crop.farmerName,
              cropId: crop.id,
            ),
            icon: const Icon(Icons.flag_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: SizedBox(
              height: 250,
              width: double.infinity,
              child: photo != null && photo.isNotEmpty
                  ? Image.memory(
                      base64Decode(photo),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _emojiHero(crop),
                    )
                  : _emojiHero(crop),
            ),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: Text(
                  crop.name,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const Pill(
                icon: Icons.verified,
                text: 'Verified',
                color: green,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '₱${crop.pricePerKg}/kg',
            style: const TextStyle(
              color: green,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 18),
          Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => showFarmSheet(
                context,
                session: widget.session,
                crop: crop,
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: lightGreen,
                      child: Text(
                        crop.farmerName.isEmpty
                            ? 'F'
                            : crop.farmerName.substring(0, 1).toUpperCase(),
                        style: const TextStyle(
                          color: darkGreen,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            crop.farmerName,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            [
                              if (crop.farmLocation.isNotEmpty)
                                crop.farmLocation,
                              if (distance != null) formatKm(distance),
                            ].join(' • '),
                            style: const TextStyle(color: muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Harvest details',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
          ),
          const SizedBox(height: 10),
          Text(
            '${crop.quantityKg} kg available for booking. '
            '${crop.harvestDate.isEmpty ? 'Harvest date to be confirmed.' : 'Harvest on ${crop.harvestDate}.'} '
            'Sorted and packed by the farm for bulk buyers.',
            style: const TextStyle(color: muted, height: 1.55),
          ),
          if (!_canOrder) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7E8),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFFD99A)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: orange, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Only ${crop.quantityKg} kg left, below this farm’s '
                      '${crop.moqKg} kg minimum order.',
                      style: const TextStyle(fontSize: 12, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Quantity',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      'Minimum ${crop.moqKg} kg',
                      style: const TextStyle(color: muted),
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                onPressed: quantity > crop.moqKg
                    ? () => setState(() => quantity -= _step)
                    : null,
                icon: const Icon(Icons.remove),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  '$quantity kg',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              IconButton.filledTonal(
                onPressed: quantity + _step <= crop.quantityKg
                    ? () => setState(() => quantity += _step)
                    : null,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: !_canOrder
                ? null
                : () {
                    widget.cart.add(crop, quantity);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('${crop.name} added to your cart'),
                        action: SnackBarAction(
                          label: 'VIEW CART',
                          onPressed: () {
                            Navigator.pop(context);
                            widget.onOpenCart();
                          },
                        ),
                      ),
                    );
                  },
            style: FilledButton.styleFrom(padding: const EdgeInsets.all(16)),
            child: Text(
              _canOrder
                  ? 'Add to cart  •  ${formatPeso(total)}'
                  : 'Not enough stock to order',
            ),
          ),
        ],
      ),
    );
  }

  Widget _emojiHero(CropListing crop) => Container(
        color: cropTint(crop.category),
        alignment: Alignment.center,
        child: Text(crop.emoji, style: const TextStyle(fontSize: 120)),
      );
}

/// Cart + checkout. Fees are charged once per farm and split across that
/// farm's lines, so a rider collecting one pickup is paid one base fare.
class CartSheet extends StatefulWidget {
  const CartSheet({super.key, required this.session, required this.cart});

  final AppSession session;
  final CartController cart;

  @override
  State<CartSheet> createState() => _CartSheetState();
}

class _CartSheetState extends State<CartSheet> {
  final _reference = TextEditingController();
  String _method = 'GCash';
  bool _placing = false;
  String? _error;

  @override
  void dispose() {
    _reference.dispose();
    super.dispose();
  }

  /// One delivery fee per farm, based on that farm's distance to the buyer.
  Map<String, int> _feesByFarm() {
    final buyer = widget.session.user.point;
    final fees = <String, int>{};
    final grouped = <String, List<CartLine>>{};
    for (final line in widget.cart.lines) {
      grouped.putIfAbsent(line.crop.farmerId, () => []).add(line);
    }
    grouped.forEach((farmerId, lines) {
      final farm = lines.first.crop.point;
      final distance =
          buyer != null && farm != null ? GeoService.distanceKm(buyer, farm) : 0.0;
      final kilos = lines.fold<int>(0, (sum, line) => sum + line.quantityKg);
      fees[farmerId] =
          DeliveryPricing.fee(distanceKm: distance, quantityKg: kilos);
    });
    return fees;
  }

  Future<void> _placeOrder() async {
    final user = widget.session.user;
    if (user.point == null || user.location.isEmpty) {
      setState(() => _error =
          'Add a delivery address in your profile before checking out.');
      return;
    }
    if (_method != 'Cash on delivery' && _reference.text.trim().isEmpty) {
      setState(() => _error = 'Enter your $_method reference number.');
      return;
    }
    setState(() {
      _placing = true;
      _error = null;
    });
    try {
      final fees = _feesByFarm();
      final grouped = <String, List<CartLine>>{};
      for (final line in widget.cart.lines) {
        grouped.putIfAbsent(line.crop.farmerId, () => []).add(line);
      }
      for (final entry in grouped.entries) {
        final lines = entry.value;
        final farmFee = fees[entry.key] ?? DeliveryPricing.baseFare;
        // Listings published before farms carried a contact number need a
        // lookup, otherwise the rider has nobody to call at the pickup.
        var farmerPhone = lines.first.crop.farmerPhone;
        if (farmerPhone.isEmpty) {
          final farm = await authService.database.getAccount(entry.key);
          farmerPhone = '${farm?['phone'] ?? ''}';
        }
        // Split the farm's single delivery fee across its lines so the
        // per-order rider payouts still add up to the fee charged.
        final share = (farmFee / lines.length).floor();
        for (var index = 0; index < lines.length; index++) {
          final line = lines[index];
          final crop = line.crop;
          final fee = index == lines.length - 1
              ? farmFee - share * (lines.length - 1)
              : share;
          await authService.database.createOrder({
            'buyerId': user.id,
            'buyerName': user.name,
            'buyerPhone': user.phone,
            'farmerId': crop.farmerId,
            'farmerName': crop.farmerName,
            'farmerPhone': farmerPhone,
            'cropId': crop.id,
            'cropName': crop.name,
            'quantityKg': line.quantityKg,
            'pricePerKg': crop.pricePerKg,
            'totalPrice': line.subtotal,
            'deliveryFee': fee,
            'deliveryAddress': user.location,
            'deliveryLatitude': user.latitude,
            'deliveryLongitude': user.longitude,
            'farmLocation': crop.farmLocation,
            'farmLatitude': crop.latitude,
            'farmLongitude': crop.longitude,
            'paymentMethod': _method,
            'paymentReference': _reference.text.trim(),
            'paymentStatus':
                _method == 'Cash on delivery' ? 'cod_pending' : 'submitted',
            'status': OrderStatus.placed.wire,
          });
          await authService.database.reduceCropStock(crop.id, line.quantityKg);
        }
      }
      widget.cart.clear();
      widget.session.bump();
      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Order sent to the farm. Track it under Orders.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error'.replaceFirst('Exception: ', '');
        _placing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.cart,
      builder: (context, _) {
        final lines = widget.cart.lines;
        final fees = _feesByFarm();
        final delivery = fees.values.fold<int>(0, (sum, fee) => sum + fee);
        final subtotal = widget.cart.subtotal;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            8,
            24,
            MediaQuery.of(context).viewInsets.bottom + 28,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your bulk order',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 18),
                if (lines.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 28),
                    child: Center(
                      child: Text(
                        'Your cart is empty.\nAdd a harvest from the market.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: muted, height: 1.5),
                      ),
                    ),
                  )
                else ...[
                  for (final line in lines) ...[
                    Row(
                      children: [
                        Expanded(
                          child: LineItem(
                            emoji: line.crop.emoji,
                            name: line.crop.name,
                            detail:
                                '${line.quantityKg} kg × ₱${line.crop.pricePerKg}',
                            price: formatPeso(line.subtotal),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remove',
                          onPressed: () => widget.cart.remove(line.crop.id),
                          icon: const Icon(Icons.close, size: 18),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                  ],
                  const Divider(height: 24),
                  MoneyRow(label: 'Subtotal', value: formatPeso(subtotal)),
                  MoneyRow(
                    label: 'Pooled delivery (${fees.length} farm'
                        '${fees.length == 1 ? '' : 's'})',
                    value: formatPeso(delivery),
                  ),
                  const SizedBox(height: 8),
                  MoneyRow(
                    label: 'Total',
                    value: formatPeso(subtotal + delivery),
                    strong: true,
                  ),
                  const SizedBox(height: 18),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          const Icon(Icons.location_on_outlined, color: green),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              widget.session.user.location.isEmpty
                                  ? 'No delivery address pinned yet'
                                  : widget.session.user.location,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: _method,
                    decoration: const InputDecoration(
                      labelText: 'Payment method',
                      prefixIcon: Icon(Icons.payments_outlined),
                    ),
                    items: const [
                      'GCash',
                      'Maya',
                      'MariBank',
                      'Bank transfer',
                      'Cash on delivery',
                    ]
                        .map(
                          (item) => DropdownMenuItem(
                            value: item,
                            child: Text(item),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setState(() => _method = value ?? 'GCash'),
                  ),
                  if (_method != 'Cash on delivery') ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _reference,
                      decoration: const InputDecoration(
                        labelText: 'Payment reference number',
                        prefixIcon: Icon(Icons.confirmation_number_outlined),
                      ),
                    ),
                  ],
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
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _placing ? null : _placeOrder,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Text(
                          _placing ? 'Placing order…' : 'Place order',
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class ConsumerOrders extends StatelessWidget {
  const ConsumerOrders({super.key, required this.session});

  final AppSession session;

  @override
  Widget build(BuildContext context) {
    return LiveBuilder<List<AgriOrder>>(
      session: session,
      load: () => authService.database.listAgriOrders(buyerId: session.user.id),
      builder: (context, data) {
        final orders = data.value ?? const <AgriOrder>[];
        final active = orders.where((order) => order.status.isOpen).toList();
        final past = orders.where((order) => !order.status.isOpen).toList();
        return LiveRefreshView(
          loading: data.loading,
          onRefresh: data.reload,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
            children: [
              const PageHeader(
                eyebrow: 'MY PURCHASES',
                title: 'Orders',
                subtitle: 'Track every harvest from farm to your door.',
              ),
              const SizedBox(height: 22),
              if (data.error != null && orders.isEmpty)
                LiveErrorCard(
                  message: data.errorMessage,
                  onRetry: data.reload,
                )
              else if (orders.isEmpty)
                const EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'No orders yet',
                  message: 'Book a harvest from the market to get started.',
                ),
              for (final order in active) ...[
                ActiveOrderCard(
                  order: order,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DeliveryTracking(
                        session: session,
                        orderId: order.id,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              for (final order in past) ...[
                PastOrderCard(
                  id: order.reference,
                  emoji: order.emoji,
                  name: order.cropName,
                  detail: '${order.quantityKg} kg • ${order.farmerName}',
                  price: formatPeso(order.grandTotal),
                  statusText: order.status == OrderStatus.delivered
                      ? 'DELIVERED'
                      : 'CANCELLED',
                  statusIcon: order.status == OrderStatus.delivered
                      ? Icons.check_circle
                      : Icons.cancel,
                  statusColor:
                      order.status == OrderStatus.delivered ? green : muted,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DeliveryTracking(
                        session: session,
                        orderId: order.id,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// The in-transit card from the mockup, driven by a real order.
class ActiveOrderCard extends StatelessWidget {
  const ActiveOrderCard({super.key, required this.order, required this.onTap});

  final AgriOrder order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Pill(
                    icon: orderStatusIcon(order.status),
                    text: order.status.label.toUpperCase(),
                    color: order.status.isWithRider ? green : orange,
                  ),
                  const Spacer(),
                  Text(
                    order.reference,
                    style: const TextStyle(
                      color: muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              LineItem(
                emoji: order.emoji,
                name: order.cropName,
                detail: '${order.quantityKg} kg • ${order.farmerName}',
                price: formatPeso(order.grandTotal),
              ),
              const Divider(height: 28),
              Row(
                children: [
                  Icon(
                    order.status.isWithRider
                        ? Icons.local_shipping
                        : Icons.schedule,
                    color: green,
                    size: 19,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      consumerStatusLine(order),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

IconData orderStatusIcon(OrderStatus status) => switch (status) {
      OrderStatus.placed => Icons.receipt_long,
      OrderStatus.preparing => Icons.inventory_2_outlined,
      OrderStatus.readyForPickup => Icons.inventory_2,
      OrderStatus.riderAssigned => Icons.person_pin_circle,
      OrderStatus.pickedUp => Icons.local_shipping_outlined,
      OrderStatus.inTransit => Icons.local_shipping,
      OrderStatus.delivered => Icons.check_circle,
      OrderStatus.cancelled => Icons.cancel,
    };

String consumerStatusLine(AgriOrder order) => switch (order.status) {
      OrderStatus.placed => 'Waiting for the farm to confirm',
      OrderStatus.preparing => 'The farm is packing your order',
      OrderStatus.readyForPickup => 'Packed — waiting for a rider',
      OrderStatus.riderAssigned =>
        '${order.riderName.isEmpty ? 'A rider' : order.riderName} is heading to the farm',
      OrderStatus.pickedUp => 'Picked up from the farm',
      OrderStatus.inTransit => 'On the way to your address',
      OrderStatus.delivered => 'Delivered',
      OrderStatus.cancelled => 'Order cancelled',
    };

class DeliveryTracking extends StatelessWidget {
  const DeliveryTracking({
    super.key,
    required this.session,
    required this.orderId,
  });

  final AppSession session;
  final String orderId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Track delivery')),
      body: LiveBuilder<AgriOrder?>(
        session: session,
        // Tracking is the one screen that benefits from a tight poll: the pin
        // should keep up with the rider without the buyer touching anything.
        interval: const Duration(seconds: 6),
        load: () => authService.database.getOrder(orderId),
        builder: (context, data) {
          final order = data.value;
          if (order == null) {
            return LiveErrorCard(
              message: data.errorMessage.isEmpty
                  ? 'This order is no longer available.'
                  : data.errorMessage,
              onRetry: data.reload,
            );
          }
          final stops = <MapStop>[
            if (order.pickupPoint != null)
              MapStop(
                point: order.pickupPoint!,
                label: order.farmerName,
                icon: Icons.agriculture,
                color: orange,
              ),
            if (order.dropPoint != null)
              MapStop(
                point: order.dropPoint!,
                label: 'Your address',
                icon: Icons.store,
                color: green,
              ),
          ];
          return LiveRefreshView(
            loading: data.loading,
            onRefresh: data.reload,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
              children: [
                if (stops.isEmpty)
                  const EmptyState(
                    icon: Icons.location_off_outlined,
                    title: 'No map available',
                    message:
                        'This order has no pinned farm or delivery location.',
                  )
                else
                  LiveRouteMap(
                    stops: stops,
                    riderPoint: order.riderPoint,
                    showControls: false,
                  ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const CircleAvatar(
                              backgroundColor: lightGreen,
                              child: Icon(Icons.person, color: green),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    order.hasRider
                                        ? order.riderName
                                        : 'Waiting for a rider',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  Text(
                                    order.hasRider
                                        ? 'Rider${order.riderVehicle.isEmpty ? '' : ' • ${order.riderVehicle}'}'
                                        : 'A logistics partner will accept soon',
                                    style: const TextStyle(
                                      color: muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (order.hasRider && order.riderPhone.isNotEmpty)
                              IconButton.filledTonal(
                                tooltip: 'Call rider',
                                onPressed: () => launchUrl(
                                  Uri(scheme: 'tel', path: order.riderPhone),
                                ),
                                icon: const Icon(Icons.phone_outlined),
                              ),
                          ],
                        ),
                        const Divider(height: 30),
                        Row(
                          children: [
                            Icon(
                              orderStatusIcon(order.status),
                              color: green,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    consumerStatusLine(order),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  Text(
                                    _etaLine(order),
                                    style: const TextStyle(color: muted),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LineItem(
                          emoji: order.emoji,
                          name: order.cropName,
                          detail:
                              '${order.quantityKg} kg • ${order.farmerName}',
                          price: formatPeso(order.totalPrice),
                        ),
                        const Divider(height: 26),
                        MoneyRow(
                          label: 'Delivery',
                          value: formatPeso(order.deliveryFee),
                        ),
                        MoneyRow(
                          label: 'Total',
                          value: formatPeso(order.grandTotal),
                          strong: true,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${order.paymentMethod}'
                          '${order.paymentReference.isEmpty ? '' : ' • ${order.paymentReference}'}',
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Delivery progress',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 14),
                ..._timeline(order),
              ],
            ),
          );
        },
      ),
    );
  }

  String _etaLine(AgriOrder order) {
    if (order.status == OrderStatus.delivered) {
      final at = order.timeline[OrderStatus.delivered.wire];
      return at == null ? 'Completed' : 'Delivered ${formatClock(at)}';
    }
    final rider = order.riderPoint;
    final drop = order.dropPoint;
    if (rider != null && drop != null && order.status.isWithRider) {
      final km = GeoService.distanceKm(rider, drop);
      final minutes = (km / 28 * 60).round().clamp(1, 600);
      return '${formatKm(km)} away • ETA $minutes min';
    }
    if (order.routeKm > 0) {
      return 'Farm to door: ${formatKm(order.routeKm)}';
    }
    return 'Updates appear here as the order moves';
  }

  List<Widget> _timeline(AgriOrder order) {
    const steps = [
      (OrderStatus.placed, 'Order placed'),
      (OrderStatus.preparing, 'Farm is packing your order'),
      (OrderStatus.readyForPickup, 'Packed and waiting for a rider'),
      (OrderStatus.riderAssigned, 'Rider accepted the trip'),
      (OrderStatus.pickedUp, 'Picked up from the farm'),
      (OrderStatus.inTransit, 'On the way to you'),
      (OrderStatus.delivered, 'Delivered'),
    ];
    final current = order.status.step;
    return [
      for (var index = 0; index < steps.length; index++)
        TimelineItem(
          title: steps[index].$2,
          subtitle: () {
            final stamp = order.timeline[steps[index].$1.wire];
            if (stamp != null) {
              return '${formatRelativeDay(stamp)} • ${formatClock(stamp)}';
            }
            if (steps[index].$1.step == current) return 'Current status';
            return steps[index].$1.step < current ? 'Completed' : 'Pending';
          }(),
          done: steps[index].$1.step <= current,
          active: steps[index].$1.step == current,
          last: index == steps.length - 1,
        ),
    ];
  }
}

class ConsumerProfile extends StatelessWidget {
  const ConsumerProfile({super.key, required this.session});

  final AppSession session;

  @override
  Widget build(BuildContext context) {
    final user = session.user;
    return LiveBuilder<List<AgriOrder>>(
      session: session,
      load: () => authService.database.listAgriOrders(buyerId: user.id),
      builder: (context, data) {
        final orders = data.value ?? const <AgriOrder>[];
        final farms = orders.map((order) => order.farmerId).toSet().length;
        final spent = orders
            .where((order) => order.status != OrderStatus.cancelled)
            .fold<int>(0, (sum, order) => sum + order.grandTotal);
        return LiveRefreshView(
          loading: data.loading,
          onRefresh: data.reload,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              PageHeader(
                eyebrow: 'CONSUMER ACCOUNT',
                title: user.name,
                subtitle: '${user.email} • ${user.phone}',
              ),
              const SizedBox(height: 24),
              ProfileTile(
                icon: Icons.location_on_outlined,
                title: 'Delivery address',
                subtitle: user.location.isEmpty ? 'Not set yet' : user.location,
                onTap: () => openProfileEditor(context, session),
              ),
              ProfileTile(
                icon: Icons.payments_outlined,
                title: 'Spending',
                subtitle:
                    '${formatPeso(spent)} across ${orders.length} order${orders.length == 1 ? '' : 's'}',
                onTap: () {},
              ),
              ProfileTile(
                icon: Icons.favorite_border,
                title: 'Farms ordered from',
                subtitle: '$farms verified farm${farms == 1 ? '' : 's'}',
                onTap: () {},
              ),
              ProfileTile(
                icon: Icons.manage_accounts_outlined,
                title: 'Account details',
                subtitle: 'Name, phone, business, and pinned location',
                onTap: () => openProfileEditor(context, session),
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

/// "View map" from the market header — every verified farm with stock.
class FarmMapPage extends StatelessWidget {
  const FarmMapPage({super.key, required this.crops, this.origin});

  final List<CropListing> crops;
  final LatLng? origin;

  @override
  Widget build(BuildContext context) {
    final seen = <String>{};
    final stops = <MapStop>[
      for (final crop in crops)
        if (crop.point != null && seen.add(crop.farmerId))
          MapStop(
            point: crop.point!,
            label: crop.farmerName,
            icon: Icons.agriculture,
            color: orange,
          ),
      if (origin != null)
        MapStop(
          point: origin!,
          label: 'You',
          icon: Icons.store,
          color: green,
        ),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Farms near you')),
      body: stops.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(20),
              child: EmptyState(
                icon: Icons.map_outlined,
                title: 'No pinned farms yet',
                message: 'Farms appear here once they pin their location.',
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(16),
              child: LiveRouteMap(
                stops: stops,
                height: MediaQuery.of(context).size.height * .7,
                showControls: true,
              ),
            ),
    );
  }
}
