# توجيه العمل على التطبيق

هذا المستودع هو تطبيق Flutter (Android) لتدقيق الرواتب على الهاتف بنفس منطق وواجهة نظام التدقيق في LorkERP (`loorksy/ERPSYSTEM-`). لا يوجد Backend؛ كل الحساب والتخزين على الهاتف، وGoogle Sheets يُستدعى مباشرة من الهاتف. التاريخ السابق (نسخة 1.0.0 المحلية فقط) محفوظ في Git.

ابدأ بـ[README](README.md)، ثم [حالة التحقق](docs/VALIDATION.md) و[مرجع التوقيع وGoogle OAuth](docs/RELEASE_SIGNING.md).

## قواعد المنطق

- `lib/erp/` نقل حرفي لمحرك ERP (`services/payrollAuditEngine.js`، `services/payrollSearchService.js`) مع محاكاة أرقام JavaScript. أي تغيير هنا يجب أن يبقى مطابقًا لنتائج ERP؛ قارن مع كود ERP قبل التعديل.
- **قرار المالك (2026-11-16):** التطبيق = التدقيق فقط بمطابقة تامة لـERP، مع إصلاح أخطاء ERP الواضحة فقط وتوثيق كل إصلاح في README. لا تضف سلوكًا يغيّر منطق ERP، ولا تنقل العمليات المحاسبية (الوكالات الفرعية، الصندوق، المؤجل، الأرباح، ملف العضو، الاعتمادات).
- `lib/services/payroll_service.dart` يقابل `POST /api/sheet/payroll-execute`؛ `cycle_service.dart` مسارات الدورات و`/cycles/:id/sync`؛ `cycle_sync_worker.dart` يقابل `services/cycleSyncWorker.js`؛ `search_service.dart` يقابل `routes/search.js`. واجهة «تدقيق» تتبع `payrollRunAudit` (مزامنة ثم تنفيذ).
- الواجهة في `lib/ui/` تحاكي صفحات ERP (`sheet.ejs`، `payroll-google.ejs`، `search.ejs`) بنفس النصوص والحقول وألوان Tailwind وخط Tajawal.

## Google

الكتابة إلى Google **مفعّلة** منذ 2.0.0 بطلب صريح من المالك (2026-11-16) لمطابقة ERP، وبدون نافذة تأكيد كما في ERP. لم تُختبر بعد على جداول Google حقيقية ولا على جهاز Android؛ لا تصف النظام بأنه متحقق منه للتدقيق الحي حتى تتوفر أدلة جديدة. OAuth ما زال External / Testing.

## الاختبارات والبناء

لم يُسمح بتشغيل `flutter test` أو اختبارات Google/Android الحقيقية؛ اطلب إذنًا جديدًا قبل تشغيلها. (تُشغَّل نفس اختبارات `test/` عبر نسخة مؤقتة خارج المستودع بمحاكاة بسيطة لـ`flutter_test`؛ راجع VALIDATION.) يجوز التحليل الساكن وبناء APK. GitHub Actions (`.github/workflows/build-apk.yml`) يبني APK Release ولا يشغّل الاختبارات.

**تحذير أمني:** بناءً على موافقة المالك، ملف `android/app/lork-audit-release.jks` و`android/key.properties` بما فيه كلمات المرور موجودة في مستودع عام وتاريخ Git. اعتبرها مكشوفة ومخترقة؛ لا تنسخها إلى أماكن أخرى ولا تصفها بأنها محمية. لا تحذفها أو تدوّرها دون الرجوع إلى المالك لأن ذلك يؤثر على التحديثات المثبتة.

Release يبنى بـJDK 21 دون تعطيل Lint. استخدم مفتاح Release الموجود وارفع versionCode فقط بعد مراجعة أثر النشر. راجع حالة GitHub البعيدة قبل أي دفع، ولا تستخدم force-push.
