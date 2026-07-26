enum MobileRole { consumer, farmer, rider, superadmin }

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
