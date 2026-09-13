class UserSession {
  final String uid;
  final String name;
  final String email;
  final String role;
  final bool active;

  const UserSession({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    required this.active,
  });

  factory UserSession.fromMap({
    required String uid,
    required Map<String, dynamic> data,
  }) {
    return UserSession(
      uid: uid,
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      role: data['role'] ?? '',
      active: data['active'] == true,
    );
  }
}
