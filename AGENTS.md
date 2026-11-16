# توجيه العمل على التطبيق

هذا المستودع هو تطبيق Flutter (Android) لتدقيق الرواتب على الهاتف بنفس منطق وواجهة نظام التدقيق في LorkERP (`loorksy/ERPSYSTEM-`). لا يوجد Backend؛ كل الحساب والتخزين على الهاتف، وGoogle Sheets يُستدعى مباشرة من الهاتف. التاريخ السابق (نسخة 1.0.0 المحلية فقط) محفوظ في Git.

ابدأ بـ[README](README.md)، ثم [حالة التحقق](docs/VALIDATION.md) و[مرجع التوقيع وGoogle OAuth](docs/RELEASE_SIGNING.md).

## قواعد المنطق

- `lib/erp/` نقل حرفي لمحرك ERP (`services/payrollAuditEngine.js`، `services/payrollSearchService.js`) مع محاكاة أرقام JavaScript. أي تغيير هنا يجب أن يبقى مطابقًا لنتائج ERP؛ قارن مع كود ERP قبل التعديل.
- `lib/services/payroll_service.dart` يقابل `POST /api/sheet/payroll-execute`؛ `search_service.dart` يقابل `routes/search.js`؛ `cycle_service.dart` يقابل مسارات الدورات في `routes/sheet.js`. الاختلافات المقصودة موثقة في README.
- الواجهة في `lib/ui/` تحاكي صفحات ERP (`sheet.ejs`، `payroll-google.ejs`، `search.ejs`) بنفس النصوص والحقول وألوان Tailwind وخط Tajawal.
- آثار ERP المحاسبية (الوكالات الفرعية، الصندوق، المؤجل، الأرباح) خارج نطاق التطبيق.

## Google

الكتابة إلى Google **مفعّلة** منذ 2.0.0 بطلب صريح من المالك (2026-11-16) لمطابقة ERP، مع تأكيد قبل كل تدقيق يكتب على Google. لم تُختبر بعد على جداول Google حقيقية ولا على جهاز Android؛ لا تصف النظام بأنه متحقق منه للتدقيق الحي حتى تتوفر أدلة جديدة. OAuth ما زال External / Testing.

## الاختبارات والبناء

لم يُسمح بتشغيل `flutter test` أو اختبارات Google/Android الحقيقية؛ اطلب إذنًا جديدًا قبل تشغيلها. يجوز التحليل الساكن وبناء APK. GitHub Actions (`.github/workflows/build-apk.yml`) يبني APK Release ولا يشغّل الاختبارات.

**تحذير أمني:** بناءً على موافقة المالك، ملف `android/app/lork-audit-release.jks` و`android/key.properties` بما فيه كلمات المرور موجودة في مستودع عام وتاريخ Git. اعتبرها مكشوفة ومخترقة؛ لا تنسخها إلى أماكن أخرى ولا تصفها بأنها محمية. لا تحذفها أو تدوّرها دون الرجوع إلى المالك لأن ذلك يؤثر على التحديثات المثبتة.

Release يبنى بـJDK 21 دون تعطيل Lint. استخدم مفتاح Release الموجود وارفع versionCode فقط بعد مراجعة أثر النشر. راجع حالة GitHub البعيدة قبل أي دفع، ولا تستخدم force-push.
