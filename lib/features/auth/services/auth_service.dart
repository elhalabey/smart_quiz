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

  Future<void> resetPassword({
    required String email,
  }) async {
    final normalizedEmail = email.trim();

    if (normalizedEmail.isEmpty) {
      throw Exception('يرجى إدخال البريد الإلكتروني');
    }

    try {
      await _auth.sendPasswordResetEmail(
        email: normalizedEmail,
      );
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'invalid-email':
          throw Exception('البريد الإلكتروني غير صحيح');

        case 'user-not-found':
          throw Exception(
            'لا يوجد حساب مرتبط بهذا البريد الإلكتروني',
          );

        case 'too-many-requests':
          throw Exception(
            'تم إجراء محاولات كثيرة. حاول مرة أخرى لاحقًا',
          );

        default:
          throw Exception(
            'حدث خطأ أثناء إرسال رابط إعادة تعيين كلمة المرور',
          );
      }
    }
  }

Future<void> deleteAccount({
  required String password,
}) async {
  final user = _auth.currentUser;

  if (user == null) {
    throw Exception('لا يوجد مستخدم مسجل الدخول');
  }

  final email = user.email?.trim();

  if (email == null || email.isEmpty) {
    throw Exception(
      'لا يمكن حذف الحساب لأن البريد الإلكتروني غير متاح',
    );
  }

  if (password.trim().isEmpty) {
    throw Exception('يرجى إدخال كلمة المرور');
  }

  try {
    // =====================================================
    // 1. إعادة المصادقة قبل العملية الحساسة
    // =====================================================

    final credential = EmailAuthProvider.credential(
      email: email,
      password: password,
    );

    await user.reauthenticateWithCredential(credential);

    final uid = user.uid;

    // =====================================================
    // 2. قراءة بيانات المستخدم قبل حذفها
    // =====================================================

    final userRef = _firestore
        .collection('users')
        .doc(uid);

    final userSnapshot = await userRef.get();

    if (!userSnapshot.exists) {
      throw Exception('بيانات المستخدم غير موجودة');
    }

    final userData = userSnapshot.data();

    if (userData == null) {
      throw Exception('تعذر قراءة بيانات المستخدم');
    }

    final role = userData['role']?.toString();

    if (role == null || role.isEmpty) {
      throw Exception('نوع المستخدم غير معروف');
    }

    // =====================================================
    // 3. حذف البيانات الشخصية والعلاقات
    // =====================================================

    final batch = _firestore.batch();

    // users/{uid}
    batch.delete(userRef);

    // -----------------------------------------------------
    // Student
    // -----------------------------------------------------

    if (role == 'student') {
      final studentRef = _firestore
          .collection('students')
          .doc(uid);

      batch.delete(studentRef);

      // studentSubjects
      final studentSubjectsSnapshot =
          await _firestore
              .collection('studentSubjects')
              .where(
                'studentId',
                isEqualTo: uid,
              )
              .get();

      for (final doc in studentSubjectsSnapshot.docs) {
        batch.delete(doc.reference);
      }

      // parentStudents
      final parentStudentsSnapshot =
          await _firestore
              .collection('parentStudents')
              .where(
                'studentId',
                isEqualTo: uid,
              )
              .get();

      for (final doc in parentStudentsSnapshot.docs) {
        batch.delete(doc.reference);
      }
    }

    // -----------------------------------------------------
    // Parent
    // -----------------------------------------------------

    else if (role == 'parent') {
      final parentRef = _firestore
          .collection('parents')
          .doc(uid);

      batch.delete(parentRef);

      // parentStudents
      final parentStudentsSnapshot =
          await _firestore
              .collection('parentStudents')
              .where(
                'parentId',
                isEqualTo: uid,
              )
              .get();

      for (final doc in parentStudentsSnapshot.docs) {
        batch.delete(doc.reference);
      }
    }

    // -----------------------------------------------------
    // Teacher
    // -----------------------------------------------------

    else if (role == 'teacher') {
      final teacherRef = _firestore
          .collection('teachers')
          .doc(uid);

      batch.delete(teacherRef);

      // teacherSubjects
      final teacherSubjectsSnapshot =
          await _firestore
              .collection('teacherSubjects')
              .where(
                'teacherId',
                isEqualTo: uid,
              )
              .get();

      for (final doc in teacherSubjectsSnapshot.docs) {
        batch.delete(doc.reference);
      }

      // teacherAssignments
      final teacherAssignmentsSnapshot =
          await _firestore
              .collection('teacherAssignments')
              .where(
                'teacherId',
                isEqualTo: uid,
              )
              .get();

      for (final doc in teacherAssignmentsSnapshot.docs) {
        batch.delete(doc.reference);
      }
    }

    // Admin لا نحذف حسابه بالطريقة دي
    else if (role == 'admin') {
      throw Exception(
        'لا يمكن حذف حساب المدير من داخل التطبيق',
      );
    } else {
      throw Exception(
        'نوع المستخدم غير مدعوم',
      );
    }

    // =====================================================
    // 4. تنفيذ حذف Firestore
    // =====================================================

    await batch.commit();

    // =====================================================
    // 5. حذف حساب Firebase Authentication
    // =====================================================

    await user.delete();
  } on FirebaseAuthException catch (e) {
    switch (e.code) {
      case 'wrong-password':
      case 'invalid-credential':
        throw Exception('كلمة المرور غير صحيحة');

      case 'requires-recent-login':
        throw Exception(
          'يجب تسجيل الدخول مرة أخرى قبل حذف الحساب',
        );

      case 'user-not-found':
        throw Exception('الحساب غير موجود');

      case 'too-many-requests':
        throw Exception(
          'تم إجراء محاولات كثيرة. حاول مرة أخرى لاحقًا',
        );

      default:
        throw Exception(
          'حدث خطأ أثناء حذف حساب Firebase',
        );
    }
  } on FirebaseException catch (e) {
    throw Exception(
      'حدث خطأ أثناء حذف بيانات الحساب: '
      '${e.message ?? 'خطأ غير معروف'}',
    );
  }
}
Future<void> deleteAccountWithCredentials({
  required String email,
  required String password,
}) async {
  final normalizedEmail = email.trim();

  if (normalizedEmail.isEmpty) {
    throw Exception(
      'يرجى إدخال البريد الإلكتروني',
    );
  }

  if (password.isEmpty) {
    throw Exception(
      'يرجى إدخال كلمة المرور',
    );
  }

  try {
    // 1. تسجيل الدخول بالحساب الذي يريد المستخدم حذفه.
    final credential =
        await _auth.signInWithEmailAndPassword(
      email: normalizedEmail,
      password: password,
    );

    final user = credential.user;

    if (user == null) {
      throw Exception(
        'تعذر العثور على الحساب',
      );
    }

    final uid = user.uid;

    // 2. قراءة بيانات المستخدم لمعرفة الـ role.
    final userRef =
        _firestore.collection('users').doc(uid);

    final userSnapshot =
        await userRef.get();

    if (!userSnapshot.exists) {
      await _auth.signOut();

      throw Exception(
        'بيانات المستخدم غير موجودة',
      );
    }

    final userData =
        userSnapshot.data();

    if (userData == null) {
      await _auth.signOut();

      throw Exception(
        'تعذر قراءة بيانات المستخدم',
      );
    }

    final role =
        userData['role']?.toString();

    if (role == null || role.isEmpty) {
      await _auth.signOut();

      throw Exception(
        'نوع المستخدم غير معروف',
      );
    }

    // المدير لا يحذف حسابه من التطبيق.
    if (role == 'admin') {
      await _auth.signOut();

      throw Exception(
        'لا يمكن حذف حساب المدير من داخل التطبيق',
      );
    }

    // 3. تجهيز حذف البيانات الشخصية.
    final batch = _firestore.batch();

    // users/{uid}
    batch.delete(userRef);

    // =====================================================
    // STUDENT
    // =====================================================

    if (role == 'student') {
      final studentRef =
          _firestore.collection('students').doc(uid);

      batch.delete(studentRef);

      // studentSubjects
      final studentSubjectsSnapshot =
          await _firestore
              .collection('studentSubjects')
              .where(
                'studentId',
                isEqualTo: uid,
              )
              .get();

      for (final doc
          in studentSubjectsSnapshot.docs) {
        batch.delete(doc.reference);
      }

      // parentStudents
      final parentStudentsSnapshot =
          await _firestore
              .collection('parentStudents')
              .where(
                'studentId',
                isEqualTo: uid,
              )
              .get();

      for (final doc
          in parentStudentsSnapshot.docs) {
        batch.delete(doc.reference);
      }
    }

    // =====================================================
    // PARENT
    // =====================================================

    else if (role == 'parent') {
      final parentRef =
          _firestore.collection('parents').doc(uid);

      batch.delete(parentRef);

      // parentStudents
      final parentStudentsSnapshot =
          await _firestore
              .collection('parentStudents')
              .where(
                'parentId',
                isEqualTo: uid,
              )
              .get();

      for (final doc
          in parentStudentsSnapshot.docs) {
        batch.delete(doc.reference);
      }
    }

    // =====================================================
    // TEACHER
    // =====================================================

    else if (role == 'teacher') {
      final teacherRef =
          _firestore.collection('teachers').doc(uid);

      batch.delete(teacherRef);

      // teacherSubjects
      final teacherSubjectsSnapshot =
          await _firestore
              .collection('teacherSubjects')
              .where(
                'teacherId',
                isEqualTo: uid,
              )
              .get();

      for (final doc
          in teacherSubjectsSnapshot.docs) {
        batch.delete(doc.reference);
      }

      // teacherAssignments
      final teacherAssignmentsSnapshot =
          await _firestore
              .collection('teacherAssignments')
              .where(
                'teacherId',
                isEqualTo: uid,
              )
              .get();

      for (final doc
          in teacherAssignmentsSnapshot.docs) {
        batch.delete(doc.reference);
      }
    }

    else {
      await _auth.signOut();

      throw Exception(
        'نوع المستخدم غير مدعوم',
      );
    }

    // 4. حذف بيانات Firestore الشخصية.
    await batch.commit();

    // 5. آخر خطوة: حذف حساب Firebase Authentication.
    await user.delete();
  } on FirebaseAuthException catch (e) {
    switch (e.code) {
      case 'invalid-email':
        throw Exception(
          'البريد الإلكتروني غير صحيح',
        );

      case 'user-not-found':
        throw Exception(
          'لا يوجد حساب بهذا البريد الإلكتروني',
        );

      case 'wrong-password':
      case 'invalid-credential':
        throw Exception(
          'البريد الإلكتروني أو كلمة المرور غير صحيحة',
        );

      case 'too-many-requests':
        throw Exception(
          'تم إجراء محاولات كثيرة. حاول مرة أخرى لاحقًا',
        );

      case 'requires-recent-login':
        throw Exception(
          'يجب تسجيل الدخول مرة أخرى قبل حذف الحساب',
        );

      default:
        throw Exception(
          'حدث خطأ أثناء حذف حساب Firebase',
        );
    }
  } on FirebaseException catch (e) {
    throw Exception(
      'حدث خطأ أثناء حذف بيانات الحساب: '
      '${e.message ?? e.code}',
    );
  }
}

  Future<void> signOut() async {
    await _auth.signOut();
  }
}
