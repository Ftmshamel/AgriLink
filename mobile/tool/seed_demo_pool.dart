// ignore_for_file: avoid_print

import 'package:agrilink_mobile/models/agri_models.dart';
import 'package:agrilink_mobile/services/cloud_database.dart';

/// Seeds two packed orders heading to the same town so the rider Order Pool
/// has a real pooled route to show. Safe to re-run: it skips if demo orders
/// are already present.
Future<void> main() async {
  final database = CloudDatabase();

  final farmer = await database.findAccountByEmail('farmer.baterbonia@agrilink.ph');
  final buyer = await database.findAccountByEmail('consumer.fatima@agrilink.ph');
  if (farmer == null || buyer == null) {
    print('Run create_explorer_accounts.dart first.');
    return;
  }
  final crops = await database.listCrops(farmerId: farmer['id'] as String);
  if (crops.isEmpty) {
    print('No crop to order. Run create_explorer_accounts.dart first.');
    return;
  }
  final crop = crops.first;

  final existing = await database.listOrders();
  if (existing.any((order) => '${order['demoSeed'] ?? ''}' == 'pool')) {
    print('Demo pool orders already exist.');
    return;
  }

  // S&R Farm sits in San Ildefonso, Bulacan; both buyers are in Cabanatuan,
  // so the two orders group into one pooled route.
  const farmLatitude = 15.0794;
  const farmLongitude = 120.9414;

  final drops = [
    (
      name: 'Perono Food House',
      address: 'Burgos Ave, Cabanatuan City, Nueva Ecija',
      latitude: 15.4864,
      longitude: 120.9673,
      quantity: 120,
    ),
    (
      name: 'Aling Nena Carinderia',
      address: 'Maharlika Highway, Cabanatuan City, Nueva Ecija',
      latitude: 15.4931,
      longitude: 120.9702,
      quantity: 80,
    ),
  ];

  for (final drop in drops) {
    final distanceKm = 52.0;
    final fee = DeliveryPricing.fee(
      distanceKm: distanceKm,
      quantityKg: drop.quantity,
    );
    await database.createOrder({
      'demoSeed': 'pool',
      'buyerId': buyer['id'],
      'buyerName': drop.name,
      'buyerPhone': '${buyer['phone']}',
      'farmerId': farmer['id'],
      'farmerName': '${farmer['name']}',
      'farmerPhone': '${farmer['phone']}',
      'cropId': crop['id'],
      'cropName': '${crop['name']}',
      'quantityKg': drop.quantity,
      'pricePerKg': (crop['pricePerKg'] as num?)?.round() ?? 52,
      'totalPrice':
          ((crop['pricePerKg'] as num?)?.round() ?? 52) * drop.quantity,
      'deliveryFee': fee,
      'deliveryAddress': drop.address,
      'deliveryLatitude': drop.latitude,
      'deliveryLongitude': drop.longitude,
      'farmLocation': 'San Ildefonso, Bulacan',
      'farmLatitude': farmLatitude,
      'farmLongitude': farmLongitude,
      'paymentMethod': 'GCash',
      'paymentStatus': 'paid',
      'status': OrderStatus.readyForPickup.wire,
    });
    print('READY packed order for ${drop.name} (${drop.quantity} kg)');
  }
}
