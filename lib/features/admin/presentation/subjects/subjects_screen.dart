import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'add_subject_screen.dart';
import 'edit_subject_screen.dart';

class SubjectsScreen extends StatelessWidget {
  const SubjectsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'المواد',
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
                          builder: (_) => const AddSubjectScreen(),
                        ),
                      );
                    },
                    icon: const Icon(
                      Icons.add,
                    ),
                    label: const Text(
                      'إضافة مادة',
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
                      .collection('subjects')
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
                          'حدث خطأ أثناء تحميل المواد',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                    }

                    final subjects = snapshot.data?.docs ?? [];

                    if (subjects.isEmpty) {
                      return const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.menu_book_outlined,
                              size: 72,
                            ),
                            SizedBox(height: 16),
                            Text(
                              'لا توجد مواد لعرضها',
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
                      itemCount: subjects.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final subject = subjects[index].data();

                        final nameAr =
                            subject['nameAr']?.toString() ?? '';

                        final nameEn =
                            subject['nameEn']?.toString() ?? '';

                        final active =
                            subject['active'] == true;

                        return Card(
  child: InkWell(
    borderRadius: BorderRadius.circular(12),
    onTap: () {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => EditSubjectScreen(
            subjectId: subjects[index].id,
            subjectData: subject,
          ),
        ),
      );
    },
    child: ListTile(
      leading: CircleAvatar(
        child: Icon(
          active
              ? Icons.menu_book_outlined
              : Icons.block_outlined,
        ),
      ),
      title: Text(
        nameAr.isEmpty ? 'مادة بدون اسم' : nameAr,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
        ),
      ),
      subtitle: nameEn.isEmpty ? null : Text(nameEn),
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
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
