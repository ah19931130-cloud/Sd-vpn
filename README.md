# 🚀 تشغيل مشروع Voice2Action للهاكاثون

## المتطلبات
- Flutter SDK (3.0+)
- Node.js (18+)
- حساب Firebase مع Blaze (للدفع عند الاستخدام)
- حساب OpenAI مع API Key

## خطوات الإعداد

### 1. إعداد Firebase
- أنشئ مشروع Firebase من console.firebase.google.com.
- فعّل Firestore، Storage، و Functions.
- في إعدادات المشروع، أضف تطبيق Android/iOS (أو استخدم ملفات `google-services.json`/`GoogleService-Info.plist`).

### 2. إعداد مفاتيح OpenAI
- استبدل `OPENAI_API_KEY` في `functions/index.js` بمفتاحك (أو استخدم متغيرات البيئة لاحقاً).

### 3. تثبيت التبعيات
```bash
cd Voice2Action
flutter pub get
cd functions
npm install
