import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'add_teacher_screen.dart';
import 'edit_teacher_screen.dart';

class TeachersScreen extends StatelessWidget {
  const TeachersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'المعلمون',
            style: TextStyle(fontWeight: FontWeight.bold),
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
      builder: (_) => const AddTeacherScreen(),
    ),
  );
},
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text(
                      'إضافة معلم',
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
                      .collection('teachers')
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
                          'حدث خطأ أثناء تحميل المعلمين',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                    }

                    final teachers = snapshot.data?.docs ?? [];

                    if (teachers.isEmpty) {
                      return const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.person_outline,
                              size: 72,
                            ),
                            SizedBox(height: 16),
                            Text(
                              'لا يوجد معلمون لعرضهم',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(
                        16,
                        0,
                        16,
                        16,
                      ),
                      itemCount: teachers.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final teacher = teachers[index].data();

                        final teacherId =
                            teacher['userId']?.toString() ??
                                teachers[index].id;

                        final active =
                            teacher['active'] == true;

                        return FutureBuilder<
                            DocumentSnapshot<Map<String, dynamic>>>(
                          future: FirebaseFirestore.instance
                              .collection('users')
                              .doc(teacherId)
                              .get(),
                          builder: (context, userSnapshot) {
                            final user =
                                userSnapshot.data?.data();

                            final name =
                                user?['name']?.toString() ?? '';

                            final email =
                                user?['email']?.toString() ?? '';

                            return Card(
  child: InkWell(
    borderRadius: BorderRadius.circular(12),
    onTap: () {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => EditTeacherScreen(
            teacherId: teacherId,
            teacherData: teacher,
            userData: user ?? {},
          ),
        ),
      );
    },
    child: ListTile(
      leading: CircleAvatar(
        child: Icon(
          active
              ? Icons.person_outline
              : Icons.block_outlined,
        ),
      ),
      title: Text(
        name.isEmpty ? 'معلم بدون اسم' : name,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
        ),
      ),
      subtitle: email.isEmpty ? null : Text(email),
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
