import 'package:latlong2/latlong.dart';

enum MobileRole { consumer, farmer, rider, superadmin }

/// Delivery vehicles AgriLink accepts from riders.
///
/// Everything on the platform is a bulk order sold by the sack, so a pooled
/// load will not fit on a motorcycle, tricycle, or kolong-kolong. Riders must
/// register a four-wheeled vehicle, which is also what the public-service code
/// on a professional licence covers.
const deliveryVehicles = <String>[
  'Multicab (4-wheel)',
  'L300 / FB van',
  'Closed van',
  'Pickup truck',
  'Elf truck (4-wheeler)',
  '6-wheeler truck',
];

class MobileUser {
  const MobileUser({
    this.id = '',
    required this.name,
    required this.email,
    required this.password,
    required this.phone,
    required this.role,
    this.verification = const {},
  });

  final String id;
  final String name;
  final String email;
  final String password;
  final String phone;
  final MobileRole role;
  final Map<String, String> verification;

  /// Address the account pinned during signup, shown as the default
  /// delivery/pickup point.
  String get location => verification['location'] ?? '';

  double? get latitude => double.tryParse(verification['latitude'] ?? '');
  double? get longitude => double.tryParse(verification['longitude'] ?? '');

  LatLng? get point => latitude != null && longitude != null
      ? LatLng(latitude!, longitude!)
      : null;

  String get vehicle =>
      verification['vehicle'] ?? verification['vehicleType'] ?? '';

  String get payoutNumber => verification['payoutNumber'] ?? '';

  String get businessName =>
      verification['establishmentName'] ?? verification['farmName'] ?? name;

  String get verificationStatus => verification['status'] ?? 'active';

  /// Only fully approved accounts reach a role shell — pending, rejected, and
  /// suspended accounts are all held at the review screen.
  bool get isApproved => verificationStatus == 'active';

  MobileUser copyWith({
    String? name,
    String? phone,
    Map<String, String>? verification,
  }) =>
      MobileUser(
        id: id,
        name: name ?? this.name,
        email: email,
        password: password,
        phone: phone ?? this.phone,
        role: role,
        verification: verification ?? this.verification,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'password': password,
        'phone': phone,
        'role': role.name,
        'verification': verification,
      };

  factory MobileUser.fromJson(Map<String, dynamic> json) => MobileUser(
        id: json['id'] as String? ?? '',
        name: json['name'] as String,
        email: json['email'] as String,
        password: json['password'] as String? ?? '',
        phone: json['phone'] as String? ?? '',
        role: MobileRole.values.firstWhere(
          (role) => role.name == json['role'],
          orElse: () => MobileRole.consumer,
        ),
        verification: {
          ...Map<String, dynamic>.from(
            (json['verification'] ?? json['profile']) as Map? ?? const {},
          ).map((key, value) => MapEntry(key, '$value')),
          if (json['verificationStatus'] != null)
            'status': '${json['verificationStatus']}',
        },
      );
}
