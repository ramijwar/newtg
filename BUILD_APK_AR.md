# بناء APK من GitHub (بدون أندرويد ستوديو)

الـ workflow في `.github/workflows/android-apk.yml` يبني **APK تجريبي (debug)** على
خادم GitHub، وينزّلك الملف كـ Artifact. لا تحتاج Android SDK ولا Flutter على جهازك.

## 1) التشغيل

1. ارفع الكود على فرع فيه الملف `.github/workflows/android-apk.yml`.
2. في المستودع: تبويب **Actions** ← **Android APK (Debug)** ← **Run workflow**.
3. اختياري في النموذج:
   - `flutter_version` — افتراضياً `3.47.2` (نفس الإصدار الذي أُنشئ به المشروع).
   - `split_per_abi` — يعطي APK أصغر لكل معمارية بدل ملف واحد شامل.
   - `api_base_url` — رابط الـ API؛ افتراضياً `https://t3lam.site/s_api/api/v1`.
4. بعد 5–15 دقائق افتح التشغيلة، ومن أسفل الصفحة نزّل **tijarti-android-debug-\<رقم\>**.
   فكّ الضغط لتحصل على `app-debug.apk`.

## 2) التركيب على الهاتف

- فعّل «التثبيت من مصادر غير معروفة» ثم افتح الـ APK، أو عبر adb:

```bash
adb install -r app-debug.apk
```

- البناء تجريبي: يعمل ببطء أكبر من البناء النهائي، ويطلب أذونات (كاميرا، موقع، إشعارات)
  عند أول استخدام، كما هو موضح في `mobile/android/app/src/main/AndroidManifest.xml`.

## 3) ما الذي يعتمده الـ workflow من إعدادات المشروع

| العنصر | القيمة | المصدر |
|---|---|---|
| Flutter | `3.47.2` (stable) | `mobile/.metadata` |
| Dart SDK | `>=3.13.2 <4.0.0` | `mobile/pubspec.lock` |
| JDK | 17 | `mobile/android/app/build.gradle.kts` |
| Gradle | 9.3.1 | `mobile/android/gradle/wrapper/gradle-wrapper.properties` |
| AGP / Kotlin | 9.1.0 / 2.4.0 | `mobile/android/settings.gradle.kts` |
| Firebase | `mobile/android/app/google-services.json` (عميل Android، حزمة `com.tijarti.tijarti_mobile`) | مرفوع في المستودع |

`gradlew` و `gradle-wrapper.jar` و `GeneratedPluginRegistrant.java` غير مرفوعة لأن
`.gitignore` الذي تضعه Flutter يستثنيها؛ أداة `flutter build apk` تولّدها تلقائياً داخل
المشروع قبل تشغيل Gradle، فلا تحتاج رفعها.

`mobile/android/local.properties` (في الحزمة الأصلية) كان يشير إلى مسار Flutter على جهاز
المطور، وقد حُذف — كل بيئة تبني مسارها الخاص.

## 4) تحويله إلى إصدار نهائي موقّع (خطوة لاحقة اختيارية)

الإصدار النهائي لا يعمل بتوقيع debug. أنشئ مفتاحاً مرّة واحدة:

```bash
keytool -genkeypair -v -keystore tijarti-release.jks \
  -alias tijarti -keyalg RSA -keysize 2048 -validity 10000
base64 -w0 tijarti-release.jks   # الناتج يُوضع في Secret كما هو
```

ثم في المستودع: **Settings ← Secrets and variables ← Actions ← New repository secret**:

| الاسم | المحتوى |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | ناتج `base64` للملف |
| `ANDROID_KEYSTORE_PASSWORD` | كلمة مرور الـ keystore |
| `ANDROID_KEY_ALIAS` | `tijarti` |
| `ANDROID_KEY_PASSWORD` | كلمة مرور المفتاح |

وفي `mobile/android/app/build.gradle.kts` استبدل `signingConfig = signingConfigs.getByName("debug")`
بقراءة `key.properties` أو متغيرات البيئة، مع إبقاء debug كخيار احتياطي حتى يستمر
البناء العام بلا أسرار.

## 5) أعطال متكررة وحلها

- **`flutter.sdk not set in local.properties`** — يعني أن البناء شُغّل عبر `./gradlew` مباشرة.
  شغّل البناء من جذور المشروع بـ `flutter build apk` كما يفعل الـ workflow.
- **`Failed to find target with hash string 'android-XX'`** — مكوّن SDK ناقص؛ خطوة
  «Accept Android SDK licenses» تسمح لـ Gradle بتنزيله. إذا استمر، أضف
  `android-actions/setup-android@v3` بعد `setup-java`.
- **تعذّر تنزيل توزيع Gradle** — الـ workflow يستخدم `setup-java` مع `cache: gradle`، وأي
  تشغيلة لاحقة تستفيد من الكاش؛ الكاش يُبنى على بصمة ملفات Gradle.
- **استهلاك دقائق Actions** — البناء الكامل على `ubuntu-latest` يستهلك دقائق من رصيد
  المستودع الخاص؛ إن كان المستودع عاماً فالدقائق غير محدودة.
