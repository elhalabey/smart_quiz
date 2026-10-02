import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'add_student_screen.dart';
import 'edit_student_screen.dart';

class StudentsScreen extends StatelessWidget {
  const StudentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'الطلاب',
            style: TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
          centerTitle: true,
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const AddStudentScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text(
                      'إضافة طالب',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: StreamBuilder<
                    QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('students')
                      .orderBy('createdAt', descending: true)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(),
                      );
                    }

                    if (snapshot.hasError) {
                      return const Center(
                        child: Text(
                          'حدث خطأ أثناء تحميل الطلاب',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                    }

                    final students = snapshot.data?.docs ?? [];

                    if (students.isEmpty) {
                      return const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.school_outlined,
                              size: 72,
                            ),
                            SizedBox(height: 16),
                            Text(
                              'لا يوجد طلاب لعرضهم',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return FutureBuilder<
                        List<QuerySnapshot<Map<String, dynamic>>>>(
                      future: Future.wait([
                        FirebaseFirestore.instance
                            .collection('users')
                            .where('role', isEqualTo: 'student')
                            .get(),
                        FirebaseFirestore.instance
                            .collection('classes')
                            .where('active', isEqualTo: true)
                            .get(),
                      ]),
                      builder: (context, dataSnapshot) {
                        if (dataSnapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }

                        if (dataSnapshot.hasError) {
                          return const Center(
                            child: Text(
                              'حدث خطأ أثناء تحميل بيانات الطلاب',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        }

                        final results = dataSnapshot.data;

                        if (results == null || results.length < 2) {
                          return const Center(
                            child: Text(
                              'تعذر تحميل بيانات الطلاب',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        }

                        final users = results[0].docs;
                        final classes = results[1].docs;

                        final userData = <String, Map<String, dynamic>>{};

                        for (final user in users) {
                          userData[user.id] = user.data();
                        }

                        final classData = <String, Map<String, dynamic>>{};

                        for (final classDoc in classes) {
                          classData[classDoc.id] = classDoc.data();
                        }

                        return ListView.separated(
                          padding: const EdgeInsets.fromLTRB(
                            16,
                            0,
                            16,
                            16,
                          ),
                          itemCount: students.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final student = students[index].data();

                            final studentUid =
                                student['userId']?.toString() ??
                                    students[index].id;

                            final name =
                                student['name']?.toString() ?? '';

                            final studentCode =
                                student['studentCode']?.toString() ?? '';

                            final active =
                                student['active'] == true;

                            final user =
                                userData[studentUid];

                            final email =
                                user?['email']?.toString() ?? '';

                            final classId =
                                student['classId']?.toString() ?? '';

                            final classInfo =
                                classData[classId];

                            final className =
                                classInfo?['name']?.toString() ?? '';

                            return Card(
  child: InkWell(
    borderRadius: BorderRadius.circular(12),
    onTap: () {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => EditStudentScreen(
            studentId: students[index].id,
            studentData: student,
          ),
        ),
      );
    },
    child: ListTile(
      leading: CircleAvatar(
        child: Icon(
          active
              ? Icons.school_outlined
              : Icons.school,
        ),
      ),
      title: Text(
        name,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Text(
            'الكود: $studentCode',
          ),
          if (className.isNotEmpty)
            Text(
              'الفصل: $className',
            ),
          if (email.isNotEmpty)
            Text(email),
        ],
      ),
      trailing: Icon(
        active
            ? Icons.check_circle_outline
            : Icons.block_outlined,
      ),
    ),
  ),
);
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

