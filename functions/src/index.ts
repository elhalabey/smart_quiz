import {setGlobalOptions} from "firebase-functions";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {getAuth} from "firebase-admin/auth";
import {getFirestore, FieldValue} from "firebase-admin/firestore";
import {initializeApp} from "firebase-admin/app";

initializeApp();

setGlobalOptions({
  maxInstances: 10,
});

export const createStudent = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError(
      "unauthenticated",
      "يجب تسجيل الدخول أولاً."
    );
  }

  const db = getFirestore();
  const adminUid = request.auth.uid;

  const adminDoc = await db
    .collection("users")
    .doc(adminUid)
    .get();

  if (!adminDoc.exists || adminDoc.data()?.role !== "admin") {
    throw new HttpsError(
      "permission-denied",
      "ليس لديك صلاحية لإنشاء طالب."
    );
  }

  const data = request.data;

  const name = String(data?.name ?? "").trim();
  const studentCode = String(data?.studentCode ?? "").trim();
  const email = String(data?.email ?? "").trim();
  const password = String(data?.password ?? "");
  const classId = String(data?.classId ?? "").trim();
  const active = data?.active === true;

  if (!name || !studentCode || !email || !password || !classId) {
    throw new HttpsError(
      "invalid-argument",
      "بيانات الطالب غير مكتملة."
    );
  }

  if (password.length < 6) {
    throw new HttpsError(
      "invalid-argument",
      "كلمة المرور يجب أن تكون 6 أحرف على الأقل."
    );
  }

  const existingStudent = await db
    .collection("students")
    .where("studentCode", "==", studentCode)
    .limit(1)
    .get();

  if (!existingStudent.empty) {
    throw new HttpsError(
      "already-exists",
      "كود الطالب مستخدم بالفعل."
    );
  }

  let authUser;

  try {
    authUser = await getAuth().createUser({
      email,
      password,
      displayName: name,
      disabled: !active,
    });
  } catch {
    throw new HttpsError(
      "already-exists",
      "تعذر إنشاء حساب الطالب. قد يكون البريد الإلكتروني مستخدمًا بالفعل."
    );
  }

  const studentUid = authUser.uid;

  try {
    const batch = db.batch();

    const userRef = db
      .collection("users")
      .doc(studentUid);

    const studentRef = db
      .collection("students")
      .doc(studentUid);

    batch.set(userRef, {
      name,
      email,
      role: "student",
      active,
      createdAt: FieldValue.serverTimestamp(),
    });

    batch.set(studentRef, {
      userId: studentUid,
      classId,
      name,
      studentCode,
      active,
      createdAt: FieldValue.serverTimestamp(),
    });

    await batch.commit();

    return {
      success: true,
      uid: studentUid,
    };
  } catch {
    await getAuth().deleteUser(studentUid);

    throw new HttpsError(
      "internal",
      "حدث خطأ أثناء حفظ بيانات الطالب."
    );
  }
});
