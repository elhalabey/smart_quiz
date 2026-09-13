import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<Map<String, dynamic>> signIn({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    final user = credential.user;

    if (user == null) {
      throw Exception('Login failed');
    }

    final userDoc = await _firestore
        .collection('users')
        .doc(user.uid)
        .get();

    if (!userDoc.exists) {
      await _auth.signOut();
      throw Exception('User profile not found');
    }

    final data = userDoc.data();

    if (data == null || data['active'] != true) {
      await _auth.signOut();
      throw Exception('User account is inactive');
    }

    return {
      'uid': user.uid,
      ...data,
    };
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }
}
