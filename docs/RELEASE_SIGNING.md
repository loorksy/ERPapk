# مرجع إصدار Android وGoogle OAuth

المشروع الآن في جذر مستودع `loorksy/CRM`، وليس داخل `mobile/flutter_audit`.

## هوية التطبيق والتوقيع

| البيان | القيمة المتحقق منها |
|---|---|
| applicationId وnamespace | `cloud.lork.audit.standalone` |
| versionName / versionCode | `2.0.1` / `3` (البيانات أدناه عن APK 1.0.0 المتحقق منه سابقًا) |
| Release alias | `lork-audit-release` |
| المخزن والمفتاح | JKS، RSA 2048 بت |
| SHA-1 لشهادة Release | `B1:12:AB:9A:C6:2B:E1:57:DA:D6:3D:ED:8C:1E:49:B0:CB:CE:46:3B` |
| SHA-256 لشهادة Release | `41:A0:9E:71:5C:D9:D3:1A:55:E3:6B:93:1C:B0:7C:42:42:51:C6:DD:B8:59:CE:57:2D:57:1A:5D:E7:C8:7B:AB` |

الشهادة العامة: [certificates/lork-audit-release.pem](certificates/lork-audit-release.pem). بصمتا الشهادة ليستا بصمة APK.

## تحذير أمني مهم: مفتاح التوقيع منشور للعامة

بناءً على طلب المالك، يحتوي المستودع العام عمدًا على ملف المفتاح الخاص وبيانات التوقيع:

- المفتاح: `android/app/lork-audit-release.jks`
- الإعداد: `android/key.properties`، ويحتوي `storePassword` و`keyPassword` كنص صريح وalias.
- Alias: `lork-audit-release`.

تعامل مع هذا المفتاح وكلمتي مروره باعتبارها **مكشوفة/مخترقة**. يستطيع أي شخص استنساخ المستودع واستخدامها لتوقيع APK يطابق شهادة هذا التطبيق؛ وقد يتيح ذلك توزيع تطبيقات مقلدة أو تحديثات موقعة بهذه الهوية خارج قنوات Android الموثوقة. حذف الملفات من أحدث commit لاحقًا لا يمحوها من تاريخ Git أو النسخ المحلية. لا تستخدم هذا المفتاح كسرّ موثوق. لا توجد نسخة سرية أو احتياطية موثوقة متحققة منفصلة عن المستودع العام.

لا تدوّر المفتاح تلقائيًا: تغيير مفتاح التوقيع قد يمنع التحديث فوق النسخة المثبتة. قبل أي توزيع أوسع، قرر استراتيجية استجابة للتسرب وتدوير/ترحيل مدعومة من قناة التوزيع المقصودة. التطبيق منفصل عن الحزمة القديمة `cloud.lork.audit` ولا يستبدلها.

## Google Cloud وOAuth

الحساب المتحقق منه: `loorksy@gmail.com`. اسم المشروع **Lork Audit** ومعرّفه `lork-audit`.

### Release

- الاسم: **Lork Audit Standalone Release**؛ النوع Android.
- Client ID: `[OAuth client ID omitted]`.
- الحزمة: `cloud.lork.audit.standalone`.
- SHA-1 المسجّل: `B1:12:AB:9A:C6:2B:E1:57:DA:D6:3D:ED:8C:1E:49:B0:CB:CE:46:3B`.
- [صفحة عميل Release](https://console.cloud.google.com/auth/clients/[OAuth client ID omitted]?project=lork-audit).

### Debug — منفصل ولم يتغير

- الاسم: **Lork Audit Standalone Debug**.
- Client ID: `[OAuth client ID omitted]`.
- SHA-1: `9C:63:60:E7:76:95:71:AB:2D:10:2A:04:8C:2E:75:FA:91:C6:A4:BF`.

لا تخلط بصمتي Debug وRelease. لا تضف Client Secret أو Service Account إلى التطبيق.

### قيد نشر OAuth

صفحة [Audience](https://console.cloud.google.com/auth/audience?project=lork-audit) أظهرت **External / Testing**، وحساب `loorksy@gmail.com` ضمن مستخدمي الاختبار. النشر العام غير مكتمل؛ زر Publish app معطّل حتى استكمال Branding. لم تتغير حالة النشر ولم يُقدم طلب تحقق عام. لذلك APK بوضع Release، لكن OAuth ليس متاحًا لجميع المستخدمين بعد. قد يستغرق تفعيل العميل من خمس دقائق إلى بضع ساعات.

النطاقات الحالية في `lib/google/google_sheets_gateway.dart`:

- `https://www.googleapis.com/auth/spreadsheets`
- `https://www.googleapis.com/auth/drive.readonly`

إنشاء عميل OAuth لا يثبت تسجيل الدخول الفعلي أو وصول الملفات أو تفعيل APIs. عند استخدام Google Play App Signing، تحقّق من شهادة App signing الفعلية في Play Console وسجّلها كعميل Android مناسب؛ قد تختلف عن شهادة البناء المحلي.

## بناء Release والتحقق

البيئة: Flutter `3.50.0`، JDK `21`، Android compile SDK `36`، Gradle `9.5.0`، Android Gradle Plugin `9.3.1`. هدف Java/Kotlin في الكود JVM 17.

```sh
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
export ANDROID_HOME=/home/ubuntu/tooling/android-sdk
export PATH="$JAVA_HOME/bin:/home/ubuntu/tooling/flutter/bin:$PATH"
flutter pub get
flutter analyze
flutter build apk --release
```

لم تُشغّل اختبارات Flutter أو Google أو Android، ولم يُشغّل التطبيق على جهاز. كانت محاولة JDK 17 تتعطل داخل Lint بخطأ `java.util.List.removeLast()`؛ نجح البناء مع JDK 21 دون تعطيل Lint. بقي تحذير مستقبلي بخصوص Kotlin Gradle Plugin في إضافتي `file_picker` و`workmanager_android`.

## APK المتحقق منه

- المسار: `build/app/outputs/flutter-apk/app-release.apk`؛ مستثنى من Git.
- الحجم: `54,306,060` بايت.
- SHA-256 للملف: `59317f2b1edd988b4e8d9b5f58feb5da9390c40c70f4716d9aeae8bb4f5d10bb`؛ الحجم: `54,306,060` بايت.
- البناء الأخير تم بعد وضع ملفات التوقيع في مسارات المستودع؛ تحقق منه `apksigner` وبصمته مسجلة أعلاه.
- `apksigner verify` أكد التوقيع v2 وبصمتي شهادة Release أعلاه، و`aapt` أكد الحزمة `cloud.lork.audit.standalone` والإصدار `1.0.0`، versionCode `1`.

```sh
openssl x509 -in docs/certificates/lork-audit-release.pem -noout -subject -dates -fingerprint -sha1
openssl x509 -in docs/certificates/lork-audit-release.pem -noout -fingerprint -sha256
```

**حدود الجاهزية:** منذ 2.0.0 الكتابة إلى Google مفعّلة لمطابقة ERP، لكنها لم تُختبر على جداول حقيقية، وOAuth ما زال Testing. نجاح البناء والتوقيع لا يثبت صلاحية التدقيق الحي. يبني GitHub Actions الآن APK 2.0.0؛ تحقق من التوقيع والبصمة من سجل التشغيل.
