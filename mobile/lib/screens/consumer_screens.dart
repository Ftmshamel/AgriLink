import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app.dart';
import '../models/agri_models.dart';
import '../services/geo.dart';
import '../services/payment_service.dart';
import '../services/session.dart';
import '../utils/app_colors.dart';
import '../widgets/live_data.dart';
import '../widgets/crop_photo.dart';
import '../widgets/live_map.dart';
import '../widgets/ui_kit.dart';
import 'shared_screens.dart';

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
                    Icon(Icons.shopping_basket, color: Colors.white, size: 66),
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
                        icon: category.icon,
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
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
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

/// Market grid tile. Shows the farmer's photo, or a plain placeholder until
/// the farmer uploads one.
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
              child: CropPhoto(photoBase64: photo, iconSize: 40),
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
  late final Future<RatingSummary> _farmRating = authService.database
      .ratingFor(farmerId: widget.crop.farmerId)
      .catchError((_) => const RatingSummary(0, 0));

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
              child: CropPhoto(photoBase64: photo, iconSize: 64),
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
                          FutureBuilder<RatingSummary>(
                            future: _farmRating,
                            builder: (context, snapshot) => Text(
                              snapshot.data?.label ?? '',
                              style: const TextStyle(
                                color: orange,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
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
            '${crop.harvestDate.isEmpty ? 'Harvest date to be confirmed.' : 'Harvest on ${formatHarvestDate(crop.harvestDate)}.'} '
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
              TextButton(
                onPressed: () async {
                  final typed = await askQuantity(
                    context,
                    min: crop.moqKg,
                    max: crop.quantityKg,
                    current: quantity,
                  );
                  if (typed != null) setState(() => quantity = typed);
                },
                child: Text(
                  '$quantity kg',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    decoration: TextDecoration.underline,
                  ),
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
                    final inCart = widget.cart.lineFor(crop.id)?.quantityKg ?? 0;
                    if (inCart + quantity > crop.quantityKg) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Only ${crop.quantityKg} kg available and you '
                            'already have $inCart kg in your cart.',
                          ),
                        ),
                      );
                      return;
                    }
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

  /// Set only after the worker confirms Xendit marked the invoice paid.
  PaymentInvoice? _paidInvoice;

  /// An invoice the buyer was sent to but has not finished paying. Reused on
  /// the next tap so they are never asked to pay the same cart twice.
  PaymentInvoice? _openInvoice;
  int _openInvoiceAmount = 0;
  final _payments = PaymentService();

  /// Every order is paid before it is created. Cash on delivery is not
  /// offered: the rider belongs to the pool, not to the farm, so there is
  /// nobody on the trip who should be holding the buyer's money.
  bool get _payingOnline => PaymentService.enabled;
  bool _placing = false;
  String? _error;

  /// Same-day unless the buyer picks a date.
  bool _scheduled = false;
  DateTime? _deliveryDate;

  /// The same-day date the buyer was last shown, to catch the 6 PM cutoff
  /// passing while the sheet is open.
  DateTime _sameDayShown = DeliveryHours.sameDayDate(DateTime.now());

  bool _useWallet = false;
  int? _walletBalance;

  DeliveryRates _rates = DeliveryRates.current;

  /// Open orders already heading to this buyer's town, not yet with a rider,
  /// for the shared-trip notice. Null while loading.
  List<AgriOrder>? _poolOrders;

  /// Once Xendit has the money the cart must not change under it.
  bool get _locked => _placing || _paidInvoice != null;

  @override
  void initState() {
    super.initState();
    _loadWallet();
    _loadRates();
    _loadPool();
  }

  Future<void> _loadRates() async {
    final rates = await authService.database.loadDeliveryRates();
    if (mounted) setState(() => _rates = rates);
  }

  String get _area => AgriOrder.areaOf(widget.session.user.location);

  Future<void> _loadPool() async {
    try {
      final orders = await authService.database.listAgriOrders();
      final mine = widget.session.user.id;
      if (!mounted) return;
      setState(() => _poolOrders = orders
          .where((order) =>
              order.status.isOpen &&
              !order.hasRider &&
              order.buyerId != mine &&
              order.dropArea == _area)
          .toList());
    } catch (_) {
      if (mounted) setState(() => _poolOrders = const []);
    }
  }

  /// The day this cart would be delivered.
  DateTime? get _targetDate =>
      _scheduled ? _deliveryDate : DeliveryHours.sameDayDate(DateTime.now());

  /// This cart as the orders it would become, so it can be priced alongside
  /// the orders it would share a trip with.
  List<AgriOrder> _draftOrders(Map<String, int> fees) {
    final user = widget.session.user;
    final grouped = <String, List<CartLine>>{};
    for (final line in widget.cart.lines) {
      grouped.putIfAbsent(line.crop.farmerId, () => []).add(line);
    }
    return [
      for (final entry in grouped.entries)
        AgriOrder.fromMap({
          'id': 'draft-${entry.key}',
          'buyerId': user.id,
          'farmerId': entry.key,
          'quantityKg': entry.value
              .fold<int>(0, (sum, line) => sum + line.quantityKg),
          'deliveryFee': fees[entry.key] ?? DeliveryPricing.fallbackFee,
          'deliveryLatitude': user.latitude,
          'deliveryLongitude': user.longitude,
          'farmLatitude': entry.value.first.crop.latitude,
          'farmLongitude': entry.value.first.crop.longitude,
        }),
    ];
  }

  Widget _poolNotice(Map<String, int> fees) {
    final all = _poolOrders;
    final date = _targetDate;
    if (all == null || date == null || _area == 'Unassigned area') {
      return const SizedBox.shrink();
    }
    final mates = all.where((order) => order.dueDate == date).toList();
    final soloTotal = fees.values.fold<int>(0, (sum, fee) => sum + fee);
    final firstSchedulable = DeliveryHours.firstScheduleDate(DateTime.now());

    // Other days a trip to this town is already forming.
    final otherDays = <DateTime, int>{};
    for (final order in all) {
      final day = order.dueDate;
      if (day == date || day.isBefore(firstSchedulable)) continue;
      otherDays[day] = (otherDays[day] ?? 0) + 1;
    }
    final suggestions = otherDays.keys.toList()..sort();

    final shared = mates.isNotEmpty;
    var sharedFee = soloTotal;
    if (shared) {
      final drafts = _draftOrders(fees);
      final shares = PoolPricing.shares([...drafts, ...mates], _rates);
      sharedFee = drafts.fold<int>(
        0,
        (sum, draft) => sum + (shares[draft.id] ?? draft.deliveryFee),
      );
    }
    final saving = soloTotal - sharedFee;
    final day = formatDeliveryDate(date);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: shared ? lightGreen : const Color(0xFFFFF1DD),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                shared ? Icons.groups_2_outlined : Icons.person_outline,
                color: shared ? green : orange,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  shared
                      ? 'Shared trip: ${plural(mates.length, 'other order')} '
                          'to $_area on $day'
                      : 'No shared trip to $_area on $day yet',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            shared && saving > 0
                ? 'You pay ${formatPeso(soloTotal)} delivery now. Sharing the '
                    'trip should bring it down to about '
                    '${formatPeso(sharedFee)}; the ${formatPeso(saving)} '
                    'difference goes back to your AgriLink wallet when a '
                    'rider takes the trip.'
                : 'You pay the full trip fee of ${formatPeso(soloTotal)}. If '
                    'other buyers in $_area book the same day, the trip is '
                    'shared and the difference goes back to your AgriLink '
                    'wallet.',
            style: const TextStyle(fontSize: 12, height: 1.4),
          ),
          if (!shared && suggestions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Trips already going to $_area:',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final option in suggestions.take(4))
                  ActionChip(
                    avatar: const Icon(Icons.event, size: 16),
                    label: Text(
                      '${formatDeliveryDate(option)} • '
                      '${plural(otherDays[option]!, 'order')}',
                    ),
                    onPressed: _locked
                        ? null
                        : () => setState(() {
                              _scheduled = true;
                              _deliveryDate = option;
                            }),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _loadWallet() async {
    try {
      final balance =
          await authService.database.walletBalance(widget.session.user.id);
      if (mounted) setState(() => _walletBalance = balance);
    } catch (_) {
      // Without a balance the wallet option simply stays unavailable.
    }
  }

  Future<void> _openWallet() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => WalletPage(session: widget.session)),
    );
    await _loadWallet();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final first = DeliveryHours.firstScheduleDate(now);
    final last = dateOnly(now).add(const Duration(days: 60));
    final suggested =
        dateOnly(now).add(const Duration(days: AgriOrder.cancelNoticeDays + 1));
    final current = _deliveryDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: current != null && !current.isBefore(first)
          ? current
          : suggested.isBefore(first)
              ? first
              : suggested,
      firstDate: first,
      lastDate: last,
      helpText: 'Delivery date',
    );
    if (picked != null) setState(() => _deliveryDate = dateOnly(picked));
  }

  @override
  void dispose() {
    _reference.dispose();
    super.dispose();
  }

  /// Straight-line distance from each farm in the cart to the buyer.
  Map<String, ({String farm, double km})> _farmDistances() {
    final buyer = widget.session.user.point;
    final result = <String, ({String farm, double km})>{};
    for (final line in widget.cart.lines) {
      final farm = line.crop.point;
      result.putIfAbsent(
        line.crop.farmerId,
        () => (
          farm: line.crop.farmerName,
          km: buyer != null && farm != null
              ? GeoService.distanceKm(buyer, farm)
              : 0.0,
        ),
      );
    }
    return result;
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
      final distance = buyer != null && farm != null
          ? GeoService.distanceKm(buyer, farm)
          : 0.0;
      final kilos = lines.fold<int>(0, (sum, line) => sum + line.quantityKg);
      fees[farmerId] =
          _rates.fee(distanceKm: distance, quantityKg: kilos);
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
    final now = DateTime.now();
    if (_scheduled && _deliveryDate == null) {
      setState(() => _error = 'Pick a delivery date.');
      return;
    }
    if (_scheduled &&
        _deliveryDate!.isBefore(DeliveryHours.firstScheduleDate(now))) {
      setState(() => _error = 'That date is no longer available. Pick a '
          'later delivery date.');
      return;
    }
    // The screen may have been open since before 6 PM; say so rather than
    // quietly moving the delivery to tomorrow.
    final sameDay = DeliveryHours.sameDayDate(now);
    if (!_scheduled && sameDay != _sameDayShown) {
      setState(() {
        _sameDayShown = sameDay;
        _error = 'It is past 6:00 PM, so this order will be delivered '
            'tomorrow, ${formatDeliveryDate(sameDay)}. Tap again to confirm.';
      });
      return;
    }
    final deliveryDate = _scheduled ? _deliveryDate! : sameDay;
    if (!_useWallet && !_payingOnline && _reference.text.trim().isEmpty) {
      setState(() => _error = 'Enter your $_method reference number.');
      return;
    }
    setState(() {
      _placing = true;
      _error = null;
    });
    // Nothing is charged until the cart still matches the farms' listings.
    if (_paidInvoice == null) {
      final problem = await _verifyCart();
      if (problem != null) {
        if (mounted) {
          setState(() {
            _error = problem;
            _placing = false;
          });
        }
        return;
      }
    }
    final total = _grandTotal();
    String? walletReference;
    var written = 0;
    try {
      if (_useWallet) {
        walletReference = await authService.database.payFromWallet(
          userId: user.id,
          amount: total,
          description: 'Order payment \u2022 ${widget.cart.lines.length} '
              'item${widget.cart.lines.length == 1 ? '' : 's'}',
        );
      } else if (_payingOnline && _paidInvoice == null) {
        final settled = await _collectPayment();
        if (!settled) {
          if (mounted) setState(() => _placing = false);
          return;
        }
      }
      final paid = walletReference != null || _paidInvoice != null;
      final fees = _feesByFarm();
      final grouped = <String, List<CartLine>>{};
      for (final line in widget.cart.lines) {
        grouped.putIfAbsent(line.crop.farmerId, () => []).add(line);
      }
      for (final entry in grouped.entries) {
        final lines = entry.value;
        final farmFee = fees[entry.key] ?? DeliveryPricing.fallbackFee;
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
            'paymentMethod':
                walletReference != null ? 'AgriLink Wallet' : _method,
            'paymentReference': walletReference ??
                _paidInvoice?.reference ??
                _reference.text.trim(),
            'paymentStatus': paid ? 'paid' : 'submitted',
            if (_paidInvoice != null) 'paymentInvoiceId': _paidInvoice!.id,
            'deliveryType': _scheduled ? 'scheduled' : 'same_day',
            'deliveryDate': deliveryDate.toIso8601String().substring(0, 10),
            // Money already in means there is nothing left for the farm to
            // accept or refuse, so a paid order arrives confirmed and the
            // farmer's only job is to pack it and book a rider.
            'status':
                paid ? OrderStatus.preparing.wire : OrderStatus.placed.wire,
          });
          written += line.subtotal + fee;
          // Off the cart the moment it exists, so a retry after a dropped
          // connection only places what is still missing.
          widget.cart.remove(crop.id);
          await authService.database.reduceCropStock(crop.id, line.quantityKg);
        }
      }
      _paidInvoice = null;
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
      // Money already taken for orders that never got written goes to the
      // wallet, whether it came from the wallet or from Xendit, so nothing is
      // lost if the buyer gives up and nothing is charged twice if they retry.
      final paidReference = walletReference ?? _paidInvoice?.reference;
      var returned = 0;
      if (paidReference != null && total > written) {
        try {
          await authService.database.reverseWalletPayment(
            userId: user.id,
            reference: paidReference,
            amount: total - written,
          );
          returned = total - written;
          if (_paidInvoice != null) {
            _paidInvoice = null;
            _useWallet = true;
          }
        } catch (_) {}
      }
      await _loadWallet();
      if (!mounted) return;
      setState(() {
        final reason = '$error'.replaceFirst('Exception: ', '');
        _error = [
          if (written > 0)
            'Some orders were placed before the connection dropped; they are '
                'under Orders.'
          else
            reason,
          if (returned > 0)
            '${formatPeso(returned)} for the rest is in your AgriLink wallet. '
                'Pay with Wallet to finish.',
        ].join(' ');
        _placing = false;
      });
    }
  }

  /// Re-reads every listing in the cart. Returns why checkout cannot go
  /// ahead, or null when stock and prices still hold.
  Future<String?> _verifyCart() async {
    try {
      for (final line in widget.cart.lines) {
        final fresh = await authService.database.getDocument(
          'mobileCrops',
          line.crop.id,
        );
        if (fresh == null) {
          widget.cart.remove(line.crop.id);
          return '${line.crop.name} is no longer listed and was removed '
              'from your cart.';
        }
        final crop = CropListing.fromMap(fresh);
        if (!crop.inStock || crop.quantityKg < crop.moqKg) {
          widget.cart.remove(line.crop.id);
          return '${line.crop.name} just sold out and was removed from your '
              'cart.';
        }
        if (crop.quantityKg < line.quantityKg) {
          widget.cart.refresh(crop);
          return 'Only ${crop.quantityKg} kg of ${crop.name} is left. '
              'Lower the quantity to continue.';
        }
        if (crop.pricePerKg != line.crop.pricePerKg) {
          widget.cart.refresh(crop);
          return '${crop.name} is now ₱${crop.pricePerKg}/kg. Check the new '
              'total, then place the order again.';
        }
      }
      return null;
    } catch (error) {
      return 'Could not check the latest stock. '
          '${'$error'.replaceFirst('Exception: ', '')}';
    }
  }

  /// Opens a Xendit checkout page and waits for the buyer to come back.
  ///
  /// Returns true only when the worker says Xendit has the money. The buyer
  /// tapping "I have paid" is not evidence of anything, so that button just
  /// triggers another check.
  Future<bool> _collectPayment() async {
    final total = _grandTotal();
    final PaymentInvoice invoice;
    final reusable = _openInvoice;
    if (reusable != null && _openInvoiceAmount == total) {
      invoice = reusable;
    } else {
      final reference = 'AGRILINK-${DateTime.now().millisecondsSinceEpoch}';
      try {
        invoice = await _payments.createInvoice(
          amount: total,
          reference: reference,
          description:
              'AgriLink order \u2022 ${widget.cart.lines.length} item'
              '${widget.cart.lines.length == 1 ? '' : 's'}',
        );
      } on PaymentException catch (error) {
        if (mounted) setState(() => _error = error.message);
        return false;
      }
      _openInvoice = invoice;
      _openInvoiceAmount = total;
      // If the buyer pays after giving up on this screen, the money is not
      // lost: the wallet credits any recorded invoice Xendit reports paid.
      try {
        await authService.database.recordCashInRequest(
          userId: widget.session.user.id,
          invoiceId: invoice.id,
          amount: total,
          reference: reference,
        );
      } catch (_) {}
    }

    final opened = await launchUrl(
      Uri.parse(invoice.url),
      mode: LaunchMode.externalApplication,
    );
    if (!opened) {
      if (mounted) {
        setState(() => _error = 'Could not open the payment page.');
      }
      return false;
    }

    if (!mounted) return false;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _PaymentWaitDialog(
        payments: _payments,
        invoice: invoice,
        amount: total,
        onChannel: _recordChannel,
      ),
    );
    if (confirmed != true) {
      if (mounted) {
        setState(() => _error = 'Payment not confirmed yet. Tap Place order '
            'to check again. If you pay after leaving, the amount goes to '
            'your AgriLink wallet.');
      }
      return false;
    }
    // Paid for this order, so the wallet must not credit it as well.
    try {
      await authService.database.closeCashInRequest(invoice.id, 'used');
    } catch (_) {}
    _paidInvoice = invoice;
    _openInvoice = null;
    return true;
  }

  /// Xendit names the channel only after the money lands, so this is the
  /// earliest the app can honestly say how the buyer paid.
  void _recordChannel(String channel) {
    if (channel.isEmpty) return;
    _method = channel;
  }

  String _cancelPolicy() {
    if (!_scheduled) {
      final now = DateTime.now();
      final String when;
      if (DeliveryHours.pastCutoff(now)) {
        when = 'Orders after 6:00 PM are delivered tomorrow, '
            '${formatDeliveryDate(DeliveryHours.sameDayDate(now))}, '
            'from 6:00 AM.';
      } else if (now.hour < DeliveryHours.opensAt) {
        when = 'Delivered today. Riders start at 6:00 AM.';
      } else {
        when = 'Delivered today. Order before 6:00 PM for same-day delivery.';
      }
      return '$when This order is final once placed and cannot be cancelled.';
    }
    final date = _deliveryDate;
    if (date == null) {
      return 'You can cancel a scheduled order up to '
          '${AgriOrder.cancelNoticeDays} days before delivery for a full '
          'refund to your wallet.';
    }
    final deadline =
        date.subtract(const Duration(days: AgriOrder.cancelNoticeDays));
    if (deadline.isBefore(dateOnly(DateTime.now()))) {
      return 'This date is less than ${AgriOrder.cancelNoticeDays} days away, '
          'so the order will be final once placed.';
    }
    return 'Free cancellation until ${formatDeliveryDate(deadline)}. '
        'Refunds go to your AgriLink wallet.';
  }

  Widget _walletNotice(int total) {
    final balance = _walletBalance;
    final short = balance != null && balance < total;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: short ? const Color(0xFFFFF1DD) : canvas,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            short ? Icons.warning_amber_rounded : Icons.lock_outline,
            color: short ? orange : green,
            size: 19,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              balance == null
                  ? 'Loading your wallet balance\u2026'
                  : short
                      ? 'Your wallet has ${formatPeso(balance)}. Cash in '
                          '${formatPeso(total - balance)} more to pay for '
                          'this order.'
                      : 'Paid instantly from your wallet. '
                          '${formatPeso(balance - total)} left after this.',
              style: const TextStyle(fontSize: 11.5, height: 1.4),
            ),
          ),
          if (short)
            TextButton(onPressed: _openWallet, child: const Text('Cash in')),
        ],
      ),
    );
  }

  /// What the buyer owes for the whole cart, items plus every farm's fee.
  int _grandTotal() {
    final fees = _feesByFarm();
    final items =
        widget.cart.lines.fold<int>(0, (sum, line) => sum + line.subtotal);
    final delivery = fees.values.fold<int>(0, (sum, fee) => sum + fee);
    return items + delivery;
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
                            thumb: CropThumb(
                              photoBase64: line.crop.photoBase64,
                            ),
                            name: line.crop.name,
                            detail:
                                '${line.quantityKg} kg × ₱${line.crop.pricePerKg}',
                            price: formatPeso(line.subtotal),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remove',
                          onPressed: _locked
                              ? null
                              : () => widget.cart.remove(line.crop.id),
                          icon: const Icon(Icons.close, size: 18),
                        ),
                      ],
                    ),
                    _QuantityStepper(
                      line: line,
                      enabled: !_locked,
                      onChanged: (kg) =>
                          widget.cart.setQuantity(line.crop.id, kg),
                    ),
                    const SizedBox(height: 10),
                  ],
                  const Divider(height: 24),
                  MoneyRow(label: 'Subtotal', value: formatPeso(subtotal)),
                  MoneyRow(
                    label: 'Pooled delivery (${fees.length} farm'
                        '${fees.length == 1 ? '' : 's'})',
                    value: formatPeso(delivery),
                  ),
                  for (final entry in _farmDistances().entries)
                    Text(
                      '${entry.value.farm} • ${formatKm(entry.value.km)} away '
                      '• ${formatPeso(fees[entry.key] ?? 0)}',
                      style: const TextStyle(color: muted, fontSize: 11.5),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    'A four-wheel trip costs ${formatPeso(_rates.baseFare)} '
                    'plus ${formatPeso(_rates.perKilometre)}/km and '
                    '₱${_rates.perKiloHandling}/kg, once per farm. The '
                    'per-km rate follows diesel at '
                    '${formatPeso(_rates.dieselPerLitre)}/L, since vans '
                    'return empty.',
                    style: const TextStyle(
                      color: muted,
                      fontSize: 11,
                      height: 1.4,
                    ),
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
                  const SizedBox(height: 18),
                  const Text(
                    'Delivery',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(
                        value: false,
                        icon: const Icon(Icons.bolt),
                        label: Text(
                          DeliveryHours.pastCutoff(DateTime.now())
                              ? 'Tomorrow'
                              : 'Same day',
                        ),
                      ),
                      const ButtonSegment(
                        value: true,
                        icon: Icon(Icons.event),
                        label: Text('Schedule'),
                      ),
                    ],
                    selected: {_scheduled},
                    onSelectionChanged: (value) =>
                        setState(() => _scheduled = value.first),
                  ),
                  if (_scheduled) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.calendar_month_outlined),
                      label: Text(
                        _deliveryDate == null
                            ? 'Pick a delivery date'
                            : formatDeliveryDate(_deliveryDate!),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  _poolNotice(fees),
                  const SizedBox(height: 8),
                  Text(
                    _cancelPolicy(),
                    style: const TextStyle(
                      color: muted,
                      fontSize: 11.5,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Payment',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: false,
                        icon: Icon(Icons.phone_iphone),
                        label: Text('GCash'),
                      ),
                      ButtonSegment(
                        value: true,
                        icon: Icon(Icons.account_balance_wallet_outlined),
                        label: Text('Wallet'),
                      ),
                    ],
                    selected: {_useWallet},
                    onSelectionChanged: _paidInvoice != null
                        ? null
                        : (value) => setState(() => _useWallet = value.first),
                  ),
                  const SizedBox(height: 12),
                  if (_useWallet)
                    _walletNotice(subtotal + delivery)
                  else ...[
                  if (!PaymentService.enabled)
                    DropdownButtonFormField<String>(
                      initialValue: _method,
                      decoration: const InputDecoration(
                        labelText: 'Payment method',
                        prefixIcon: Icon(Icons.payments_outlined),
                      ),
                      items:
                          const ['GCash', 'Maya', 'MariBank', 'Bank transfer']
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
                  if (_payingOnline) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: canvas,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.lock_outline,
                              color: green, size: 19),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _paidInvoice == null
                                  ? 'Pay on the next screen. GCash, Maya, card, '
                                      'or bank \u2014 you pick there, and there is '
                                      'no reference number to type.'
                                  : 'Paid \u2022 $_method \u2022 '
                                      '${_paidInvoice!.reference}',
                              style:
                                  const TextStyle(fontSize: 11.5, height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (_method != 'Cash on delivery') ...[
                    const SizedBox(height: 12),
                    _ManualPayTo(
                      method: _method,
                      amount: subtotal + delivery,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _reference,
                      decoration: const InputDecoration(
                        labelText: 'Payment reference number',
                        prefixIcon: Icon(Icons.confirmation_number_outlined),
                      ),
                    ),
                  ],
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
                      onPressed: _placing ||
                              (_useWallet &&
                                  (_walletBalance ?? 0) < subtotal + delivery)
                          ? null
                          : _placeOrder,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Text(
                          _placing
                              ? 'Placing order…'
                              : _useWallet
                                  ? 'Pay ${formatPeso(subtotal + delivery)} '
                                      'from wallet'
                                  : 'Place order',
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

/// Where to send money when there is no payment gateway, so the buyer is not
/// asked for a reference number without being told who to pay.
class _ManualPayTo extends StatelessWidget {
  const _ManualPayTo({required this.method, required this.amount});

  final String method;
  final int amount;

  static const number = String.fromEnvironment('AGRILINK_GCASH_NUMBER');
  static const name = String.fromEnvironment(
    'AGRILINK_GCASH_NAME',
    defaultValue: 'AgriLink',
  );

  @override
  Widget build(BuildContext context) {
    final configured = number.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: configured ? lightGreen : const Color(0xFFFFF1DD),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            configured ? Icons.send_to_mobile : Icons.warning_amber_rounded,
            color: configured ? green : orange,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: configured
                ? Text.rich(
                    TextSpan(
                      style: const TextStyle(fontSize: 12, height: 1.45),
                      children: [
                        TextSpan(text: 'Send ${formatPeso(amount)} via '),
                        TextSpan(
                          text: method,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const TextSpan(text: ' to '),
                        const TextSpan(
                          text: '$name • $number',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const TextSpan(
                          text: ', then enter the reference number from '
                              'your receipt. The farm confirms it before '
                              'packing.',
                        ),
                      ],
                    ),
                  )
                : const Text(
                    'No payment account is set up in this build, so there '
                    'is nowhere to send money. Pay with your AgriLink Wallet '
                    'instead.',
                    style: TextStyle(fontSize: 12, height: 1.45),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Lets a bulk buyer type a quantity instead of tapping + dozens of times.
Future<int?> askQuantity(
  BuildContext context, {
  required int min,
  required int max,
  required int current,
}) async {
  final controller = TextEditingController(text: '$current');
  String? error;
  final result = await showDialog<int>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) {
        void submit() {
          final value = int.tryParse(controller.text.trim());
          if (value == null || value < min || value > max) {
            setDialogState(() => error = 'Enter $min to $max kg.');
            return;
          }
          Navigator.pop(dialogContext, value);
        }

        return AlertDialog(
          title: const Text('Quantity'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            onSubmitted: (_) => submit(),
            decoration: InputDecoration(
              suffixText: 'kg',
              helperText: 'Minimum $min kg • $max kg available',
              errorText: error,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(onPressed: submit, child: const Text('Set')),
          ],
        );
      },
    ),
  );
  controller.dispose();
  return result;
}

/// Changes a cart line in steps of the farm's minimum order, never below it
/// and never past the stock the listing had when it was added.
class _QuantityStepper extends StatelessWidget {
  const _QuantityStepper({
    required this.line,
    required this.enabled,
    required this.onChanged,
  });

  final CartLine line;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final crop = line.crop;
    final step = crop.moqKg > 0 ? crop.moqKg : 1;
    final kg = line.quantityKg;
    return Row(
      children: [
        const SizedBox(width: 64),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'Less',
          onPressed: enabled && kg - step >= crop.moqKg
              ? () => onChanged(kg - step)
              : null,
          icon: const Icon(Icons.remove_circle_outline, size: 22),
        ),
        InkWell(
          onTap: !enabled
              ? null
              : () async {
                  final typed = await askQuantity(
                    context,
                    min: crop.moqKg,
                    max: crop.quantityKg,
                    current: kg,
                  );
                  if (typed != null) onChanged(typed);
                },
          child: Text(
            '$kg kg',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'More',
          onPressed: enabled && kg + step <= crop.quantityKg
              ? () => onChanged(kg + step)
              : null,
          icon: const Icon(Icons.add_circle_outline, size: 22),
        ),
        const Spacer(),
        Text(
          '${crop.quantityKg} kg left',
          style: const TextStyle(color: muted, fontSize: 11),
        ),
      ],
    );
  }
}

/// Sits between the buyer and their order while Xendit is being paid.
///
/// It checks by itself every few seconds, so the buyer only has to pay and
/// come back. The manual button is a shortcut for the impatient, not a way in:
/// every check asks the worker, which asks Xendit. Saying you paid proves
/// nothing here, and the order is not written until Xendit says the money
/// arrived.
class _PaymentWaitDialog extends StatefulWidget {
  const _PaymentWaitDialog({
    required this.payments,
    required this.invoice,
    required this.amount,
    required this.onChannel,
  });

  final PaymentService payments;
  final PaymentInvoice invoice;
  final int amount;
  final ValueChanged<String> onChannel;

  @override
  State<_PaymentWaitDialog> createState() => _PaymentWaitDialogState();
}

class _PaymentWaitDialogState extends State<_PaymentWaitDialog> {
  Timer? _poll;
  bool _checking = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    // Xendit needs a moment to register a payment, so the first look is not
    // immediate; after that keep watching until it lands.
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _check());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _check({bool manual = false}) async {
    if (_checking) return;
    setState(() {
      _checking = true;
      if (manual) _message = null;
    });
    try {
      final status = await widget.payments.check(widget.invoice.id);
      if (!mounted) return;
      if (status.paid) {
        widget.onChannel(status.channel);
        _poll?.cancel();
        Navigator.pop(context, true);
        return;
      }
      if (manual) {
        setState(() => _message =
            'Xendit has not received the payment yet. Finish paying and this '
                'will update on its own.');
      }
    } on PaymentException catch (error) {
      // A dropped check is not a failed payment - keep watching, and only say
      // something when the buyer asked.
      if (mounted && manual) setState(() => _message = error.message);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Waiting for payment'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pay ${formatPeso(widget.amount)} on the page that just opened. '
            'This screen updates by itself once Xendit receives it.',
            style: const TextStyle(height: 1.4),
          ),
          const SizedBox(height: 14),
          const Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Checking with Xendit\u2026',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Reference ${widget.invoice.reference}',
            style: const TextStyle(color: muted, fontSize: 12),
          ),
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(
              _message!,
              style: const TextStyle(
                color: Color(0xFFB42318),
                fontWeight: FontWeight.w700,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => launchUrl(
            Uri.parse(widget.invoice.url),
            mode: LaunchMode.externalApplication,
          ),
          child: const Text('Reopen page'),
        ),
        FilledButton(
          onPressed: _checking ? null : () => _check(manual: true),
          child: const Text('Check now'),
        ),
      ],
    );
  }
}

/// The buyer's AgriLink wallet: balance, cash-in, and every peso's history.
///
/// Cash-ins go through the same Xendit worker as checkout. The invoice is
/// recorded before the buyer leaves the app, so one paid after they closed the
/// waiting dialog is still credited the next time this page opens.
class WalletPage extends StatefulWidget {
  const WalletPage({super.key, required this.session});

  final AppSession session;

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> {
  final _payments = PaymentService();
  bool _busy = false;

  static const minCashIn = 100;
  static const maxCashIn = 50000;

  String get _userId => widget.session.user.id;

  Future<List<WalletTransaction>> _load() async {
    await _settlePending();
    return authService.database.listWalletTransactions(_userId);
  }

  /// Credits any cash-in Xendit has confirmed since it was started.
  Future<void> _settlePending() async {
    if (!PaymentService.enabled) return;
    try {
      final pending = await authService.database.listPendingCashIns(_userId);
      for (final request in pending) {
        final invoiceId = '${request['id']}';
        final status = await _payments.check(invoiceId);
        if (status.paid && status.amount > 0) {
          await authService.database.creditCashIn(
            userId: _userId,
            amount: status.amount,
            invoiceId: invoiceId,
            reference: '${request['reference'] ?? ''}',
            channel: status.channel,
          );
          await authService.database.closeCashInRequest(invoiceId, 'credited');
        } else if (status.expired) {
          await authService.database.closeCashInRequest(invoiceId, 'expired');
        }
      }
    } catch (_) {
      // Settling is retried on every refresh; a failed check is not an error
      // worth showing over the balance.
    }
  }

  Future<void> _cashIn() async {
    final amount = await showDialog<int>(
      context: context,
      builder: (_) => const _CashInDialog(min: minCashIn, max: maxCashIn),
    );
    if (amount == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final credited = PaymentService.enabled
          ? await _cashInOnline(amount)
          : await _cashInDemo(amount);
      if (!mounted || !credited) return;
      widget.session.bump();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${formatPeso(amount)} added to your wallet.')),
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

  Future<bool> _cashInOnline(int amount) async {
    final reference = 'AGRILINK-WALLET-${DateTime.now().millisecondsSinceEpoch}';
    final invoice = await _payments.createInvoice(
      amount: amount,
      reference: reference,
      description: 'AgriLink wallet cash-in',
    );
    await authService.database.recordCashInRequest(
      userId: _userId,
      invoiceId: invoice.id,
      amount: amount,
      reference: reference,
    );
    final opened = await launchUrl(
      Uri.parse(invoice.url),
      mode: LaunchMode.externalApplication,
    );
    if (!opened) throw Exception('Could not open the payment page.');
    if (!mounted) return false;
    var channel = '';
    final paid = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PaymentWaitDialog(
        payments: _payments,
        invoice: invoice,
        amount: amount,
        onChannel: (value) => channel = value,
      ),
    );
    if (paid != true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'If you finish paying later, the money appears here '
              'automatically.',
            ),
          ),
        );
      }
      return false;
    }
    // Credit what Xendit says was paid, not what the app asked for.
    final status = await _payments.check(invoice.id);
    await authService.database.creditCashIn(
      userId: _userId,
      amount: status.amount > 0 ? status.amount : amount,
      invoiceId: invoice.id,
      reference: reference,
      channel: channel,
    );
    await authService.database.closeCashInRequest(invoice.id, 'credited');
    return true;
  }

  /// Without a payment worker there is nothing to verify a payment against,
  /// so a development build adds clearly labelled demo funds instead — the
  /// same approach the password reset takes without an email provider.
  Future<bool> _cashInDemo(int amount) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Development build'),
        content: Text(
          'No payment gateway is configured, so no real money moves. '
          'Add ${formatPeso(amount)} of demo funds to this wallet?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Add demo funds'),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;
    final id = 'demo-${DateTime.now().millisecondsSinceEpoch}';
    return authService.database.creditCashIn(
      userId: _userId,
      amount: amount,
      invoiceId: id,
      reference: id,
      channel: 'demo funds',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AgriLink Wallet')),
      body: LiveBuilder<List<WalletTransaction>>(
        session: widget.session,
        load: _load,
        builder: (context, data) {
          final entries = data.value ?? const <WalletTransaction>[];
          final balance =
              entries.fold<int>(0, (sum, entry) => sum + entry.amount);
          return LiveRefreshView(
            loading: data.loading,
            onRefresh: data.reload,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                Card(
                  color: green,
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Available balance',
                          style: TextStyle(color: Color(0xFFD8EAD1)),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          data.value == null ? '—' : formatPeso(balance),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: green,
                          ),
                          onPressed: _busy ? null : _cashIn,
                          icon: const Icon(Icons.add),
                          label: const Text('Cash in'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Pay for orders with your balance. Refunds for cancelled '
                  'orders always come back here. Wallet funds cannot be '
                  'withdrawn.',
                  style: TextStyle(color: muted, fontSize: 12, height: 1.4),
                ),
                const SizedBox(height: 22),
                const SectionTitle(title: 'History', action: ''),
                const SizedBox(height: 10),
                if (data.error != null && entries.isEmpty)
                  LiveErrorCard(
                    message: data.errorMessage,
                    onRetry: data.reload,
                  )
                else if (entries.isEmpty)
                  const EmptyState(
                    icon: Icons.account_balance_wallet_outlined,
                    title: 'No transactions yet',
                    message: 'Cash in to start paying with your wallet.',
                  )
                else
                  for (final entry in entries)
                    Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              entry.amount >= 0 ? lightGreen : canvas,
                          child: Icon(
                            switch (entry.type) {
                              WalletEntryType.cashIn => Icons.add_card,
                              WalletEntryType.payment => Icons.shopping_bag,
                              WalletEntryType.refund => Icons.undo,
                            },
                            color: entry.amount >= 0 ? green : muted,
                          ),
                        ),
                        title: Text(
                          entry.description.isEmpty
                              ? entry.type.label
                              : entry.description,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          [
                            if (entry.createdAt != null)
                              '${formatRelativeDay(entry.createdAt!)} • '
                                  '${formatClock(entry.createdAt!)}',
                            if (entry.reference.isNotEmpty) entry.reference,
                          ].join('\n'),
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

class _CashInDialog extends StatefulWidget {
  const _CashInDialog({required this.min, required this.max});

  final int min;
  final int max;

  @override
  State<_CashInDialog> createState() => _CashInDialogState();
}

class _CashInDialogState extends State<_CashInDialog> {
  final _amount = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _submit() {
    final value = int.tryParse(_amount.text.trim());
    if (value == null || value < widget.min || value > widget.max) {
      setState(() => _error = 'Enter ${formatPeso(widget.min)} to '
          '${formatPeso(widget.max)}.');
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cash in'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 8,
            children: [
              for (final preset in const [100, 500, 1000, 2000])
                ActionChip(
                  label: Text(formatPeso(preset)),
                  onPressed: () => setState(() {
                    _amount.text = '$preset';
                    _error = null;
                  }),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Amount',
              prefixText: '₱',
              errorText: _error,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Continue')),
      ],
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
                  thumb: CropThumb(cropId: order.cropId),
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
                thumb: CropThumb(cropId: order.cropId),
                name: order.cropName,
                detail: '${order.quantityKg} kg • ${order.farmerName}',
                price: formatPeso(order.grandTotal),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    order.isScheduled ? Icons.event : Icons.bolt,
                    color: order.isScheduled ? green : orange,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    deliveryScheduleLabel(order),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
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
                _ScheduleCard(session: session, order: order),
                if (order.status.isWithRider &&
                    order.deliveryCode.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _DeliveryCodeCard(code: order.deliveryCode),
                ],
                if (order.status == OrderStatus.delivered) ...[
                  const SizedBox(height: 16),
                  DeliveryProofCard(order: order),
                  const SizedBox(height: 12),
                  _ReceiptActions(session: session, order: order),
                ],
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LineItem(
                          thumb: CropThumb(cropId: order.cropId),
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
                        if (order.poolRebate > 0)
                          Text(
                            'Shared trip: ${formatPeso(order.poolRebate)} of '
                            'your delivery fee went back to your wallet.',
                            style: const TextStyle(
                              color: green,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
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

/// When the order arrives, whether it can still be cancelled, and what was
/// refunded if it was.
class _ScheduleCard extends StatefulWidget {
  const _ScheduleCard({required this.session, required this.order});

  final AppSession session;
  final AgriOrder order;

  @override
  State<_ScheduleCard> createState() => _ScheduleCardState();
}

class _ScheduleCardState extends State<_ScheduleCard> {
  bool _busy = false;

  Future<void> _cancel() async {
    final order = widget.order;
    final refund = order.refundableAmount;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel this order?'),
        content: Text(
          refund > 0
              ? '${formatPeso(refund)} goes back to your AgriLink wallet.'
              : 'Nothing has been paid yet, so there is nothing to refund.',
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
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      final refunded = await authService.database.cancelOrder(
        order.id,
        cancelledBy: 'buyer',
        restock: true,
      );
      widget.session.bump();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            refunded > 0
                ? 'Order cancelled. ${formatPeso(refunded)} is back in your '
                    'wallet.'
                : 'Order cancelled.',
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

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final deadline = order.cancelDeadline;
    final canCancel = order.canBuyerCancel(DateTime.now());
    final String policy;
    if (order.status == OrderStatus.cancelled) {
      final by = switch (order.cancelledBy) {
        'buyer' => 'You cancelled this order.',
        'farmer' => 'The farm cancelled this order.',
        _ => 'This order was cancelled.',
      };
      policy = order.isRefunded
          ? '$by ${formatPeso(order.refundedAmount)} was refunded to your '
              'AgriLink wallet.'
          : by;
    } else if (!order.status.isOpen) {
      policy = '';
    } else if (canCancel) {
      policy = 'Free cancellation until ${formatDeliveryDate(deadline!)}.';
    } else if (deadline == null) {
      policy = 'Same-day orders cannot be cancelled.';
    } else {
      policy = 'The cancellation window closed on '
          '${formatDeliveryDate(deadline)}.';
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  order.isScheduled ? Icons.event : Icons.bolt,
                  color: order.isScheduled ? green : orange,
                ),
                const SizedBox(width: 10),
                Text(
                  deliveryScheduleLabel(order),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ],
            ),
            if (policy.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(policy, style: const TextStyle(color: muted, height: 1.4)),
            ],
            if (canCancel) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _cancel,
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Cancel order'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The code the buyer reads out at the door. The rider cannot finish the
/// drop-off without it, so handing it over is the buyer's signature.
class _DeliveryCodeCard extends StatelessWidget {
  const _DeliveryCodeCard({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: lightGreen,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.password, color: green),
                SizedBox(width: 8),
                Text(
                  'Delivery code',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Center(
              child: Text(
                code,
                style: const TextStyle(
                  fontSize: 36,
                  letterSpacing: 14,
                  fontWeight: FontWeight.w900,
                  color: green,
                ),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Give this code to the rider only after you have checked your '
              'items. Never share it over the phone.',
              style: TextStyle(color: muted, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lets the buyer close the loop on a delivered order: confirm the items
/// arrived, or report that they did not.
class _ReceiptActions extends StatefulWidget {
  const _ReceiptActions({required this.session, required this.order});

  final AppSession session;
  final AgriOrder order;

  @override
  State<_ReceiptActions> createState() => _ReceiptActionsState();
}

class _ReceiptActionsState extends State<_ReceiptActions> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      widget.session.bump();
      if (!mounted) return;
      if (done.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(done)),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error'.replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    await _run(
      () => authService.database.confirmReceived(widget.order.id),
      'Thanks! Receipt confirmed.',
    );
    if (mounted) await _rate();
  }

  Future<void> _rate() async {
    final order = widget.order;
    final rating = await showDialog<_Rating>(
      context: context,
      builder: (_) => _RatingDialog(
        farmName: order.farmerName,
        riderName: order.hasRider ? order.riderName : '',
      ),
    );
    if (rating == null) return;
    await _run(
      () => authService.database.rateOrder(
        order.id,
        farmerRating: rating.farm,
        riderRating: rating.rider,
        comment: rating.comment,
      ),
      'Thanks for rating this order.',
    );
  }

  Future<void> _report() => _run(() async {
        final order = widget.order;
        final filed = await showReportSheet(
          context,
          session: widget.session,
          farmerId: order.farmerId,
          farmerName: order.farmerName,
          cropId: order.cropId,
          orderId: order.id,
          riderId: order.riderId,
          riderName: order.riderName,
        );
        if (filed) await authService.database.markDeliveryDisputed(order.id);
      }, '');

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!order.isReceiptConfirmed && !order.isDisputed)
          FilledButton.icon(
            onPressed: _busy ? null : _confirm,
            icon: const Icon(Icons.check_circle_outline),
            label: const Padding(
              padding: EdgeInsets.all(12),
              child: Text('I received my order'),
            ),
          ),
        if (order.isReceiptConfirmed && !order.isRated)
          FilledButton.icon(
            onPressed: _busy ? null : _rate,
            icon: const Icon(Icons.star_outline),
            label: const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Rate this order'),
            ),
          ),
        if (order.isRated)
          Text(
            'You rated the farm ${order.farmerRating}/5'
            '${order.riderRating > 0 ? ' and the rider ${order.riderRating}/5' : ''}.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: muted),
          ),
        if (!order.isDisputed) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _report,
            icon: const Icon(Icons.report_outlined),
            label: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                order.isReceiptConfirmed
                    ? 'Report a problem with this order'
                    : 'Not received / problem with delivery',
              ),
            ),
          ),
        ],
      ],
    );
  }
}

typedef _Rating = ({int farm, int rider, String comment});

class _RatingDialog extends StatefulWidget {
  const _RatingDialog({required this.farmName, required this.riderName});

  final String farmName;
  final String riderName;

  @override
  State<_RatingDialog> createState() => _RatingDialogState();
}

class _RatingDialogState extends State<_RatingDialog> {
  int _farm = 0;
  int _rider = 0;
  final _comment = TextEditingController();

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Widget _stars(int value, ValueChanged<int> onChanged) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var star = 1; star <= 5; star++)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: '$star star${star == 1 ? '' : 's'}',
              onPressed: () => setState(() => onChanged(star)),
              icon: Icon(
                star <= value ? Icons.star : Icons.star_border,
                color: orange,
              ),
            ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final hasRider = widget.riderName.isNotEmpty;
    return AlertDialog(
      title: const Text('Rate this order'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Produce from ${widget.farmName}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            _stars(_farm, (value) => _farm = value),
            if (hasRider) ...[
              const SizedBox(height: 8),
              Text(
                'Delivery by ${widget.riderName}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              _stars(_rider, (value) => _rider = value),
            ],
            const SizedBox(height: 8),
            TextField(
              controller: _comment,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Comment (optional)',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Later'),
        ),
        FilledButton(
          onPressed: _farm == 0 || (hasRider && _rider == 0)
              ? null
              : () => Navigator.pop<_Rating>(
                    context,
                    (farm: _farm, rider: _rider, comment: _comment.text),
                  ),
          child: const Text('Submit'),
        ),
      ],
    );
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
                icon: Icons.account_balance_wallet_outlined,
                title: 'AgriLink Wallet',
                subtitle: 'Balance, cash in, and refunds',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => WalletPage(session: session),
                  ),
                ),
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
