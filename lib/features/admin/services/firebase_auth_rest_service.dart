import 'dart:convert';

import 'package:http/http.dart' as http;

class FirebaseAuthRestService {
  static const String _apiKey = 'AIzaSyD3e1WiDfpkjpWu1M7YTROrU488soVj2GA';

  static const String _signUpUrl =
      'https://identitytoolkit.googleapis.com/v1/accounts:signUp';

  Future<String> createUser({
    required String email,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$_signUpUrl?key=$_apiKey'),
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'email': email.trim(),
        'password': password,
        'returnSecureToken': true,
      }),
    );

    final data = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 200) {
      final error = data['error'] as Map<String, dynamic>?;
      final message = error?['message']?.toString();

      throw Exception(
        message ?? 'تعذر إنشاء حساب الطالب.',
      );
    }

    final localId = data['localId']?.toString();

    if (localId == null || localId.isEmpty) {
      throw Exception('لم يتم الحصول على معرف حساب الطالب.');
    }

    return localId;
  }
}
