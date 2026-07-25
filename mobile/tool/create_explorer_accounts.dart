import '../lib/cloud_database.dart';

Future<void> main() async {
  final database = CloudDatabase();
  final accounts = [
    {
      'name': 'Fatima Perono',
      'email': 'consumer.fatima@agrilink.ph',
      'password': 'Consumer2026!',
      'phone': '09170000001',
      'role': 'consumer',
      'profile': {
        'representativeName': 'Fatima Perono',
        'establishmentName': 'Perono Food House',
        'location': 'San Ildefonso, Bulacan',
        'accountPurpose': 'Restaurant / bulk buyer',
      },
    },
    {
      'name': 'Rovick Dompor',
      'email': 'rider.rovick@agrilink.ph',
      'password': 'Rider2026!',
      'phone': '09170000002',
      'role': 'rider',
      'profile': {
        'vehicle': 'L300',
        'licenseType': 'Professional Driver’s License',
        'location': 'Bulacan',
      },
    },
    {
      'name': 'Baterbonia Farm',
      'email': 'farmer.baterbonia@agrilink.ph',
      'password': 'Farmer2026!',
      'phone': '09170000003',
      'role': 'farmer',
      'profile': {
        'farmName': 'Baterbonia Farm',
        'primaryCrop': 'Rice / Bigas',
        'location': 'San Ildefonso, Bulacan',
        'barangayCertificate': 'optional_not_submitted',
      },
    },
    {
      'name': 'AgriLink Superadmin',
      'email': 'admin@agrilink.ph',
      'password': 'Admin2026!',
      'phone': '09170000004',
      'role': 'superadmin',
      'profile': {
        'access': 'Platform management',
      },
    },
  ];

  for (final account in accounts) {
    final email = account['email']! as String;
    var saved = await database.findAccountByEmail(email);
    if (saved == null) {
      saved = await database.createAccount(
        name: account['name']! as String,
        email: email,
        password: account['password']! as String,
        phone: account['phone']! as String,
        role: account['role']! as String,
        profile: Map<String, dynamic>.from(account['profile']! as Map),
      );
    }
    await database.updateDocument(
      'mobileUsers',
      saved['id']! as String,
      {'verificationStatus': 'active'},
    );
    print('READY ${account['role']}: $email');
  }

  final farmer =
      await database.findAccountByEmail('farmer.baterbonia@agrilink.ph');
  final crops = await database.listCrops(farmerId: farmer!['id'] as String);
  if (crops.isEmpty) {
    await database.createCrop({
      'farmerId': farmer['id'],
      'farmerName': 'Baterbonia Farm',
      'name': 'Palay (Bigas)',
      'quantityKg': 1000,
      'pricePerKg': 52,
      'moqKg': 25,
      'harvestDate': DateTime.now()
          .add(const Duration(days: 30))
          .toIso8601String()
          .split('T')
          .first,
      'farmLocation': 'San Ildefonso, Bulacan',
      'status': 'active',
    });
    print('READY crop: Palay (Bigas)');
  }
}
