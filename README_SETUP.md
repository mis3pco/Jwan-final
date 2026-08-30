# جوان للتوصيل — Web/PWA + Firebase

هذه النسخة مطوّرة من `index.html` المرفوع في المحادثة. الواجهة RTL ومتجاوبة للهواتف، وتعمل كتطبيق ويب/PWA ويمكن لاحقاً تغليفها إلى APK.

## 1) ربط Firebase

أنشئ مشروع Firebase ثم فعّل:
- Authentication: Email/Password وGoogle.
- Firestore Database.
- Cloud Storage.
- Cloud Functions.
- Cloud Messaging.

انسخ Web App config إلى متغير `CFG` أعلى `index.html`، وضع Web Push VAPID public key في `vapidKey`.

Firebase JS SDK المستخدم في الواجهة هو 12.18.0 وفق ملاحظات الإصدار الحالية في أغسطس 2026. Cloud Functions مضبوط على Node.js 22 لأن Node 20 و22 مدعومان حالياً، وNode 18 متوقف. 

## 2) مهم جداً: Storage

رفع الإشعارات وملفات إثبات الهوية يحتاج Cloud Storage. حالياً إنشاء/استخدام Cloud Storage for Firebase يتطلب خطة Blaze؛ ويوجد استخدام مجاني ضمن حدود الخدمة، لكن تظل وسيلة دفع مطلوبة للمشروع. راجع سياسة الأسعار قبل الإنتاج.

## 3) الصلاحيات والأمان

لا تضع كلمة مرور مدير ثابتة داخل JavaScript. النسخة السابقة كانت تحتوي بيانات دخول مدير صريحة، وتمت إزالة ذلك. المدير يدار بواسطة Firebase Custom Claims عبر `setAdminRole`.

أيضاً لا تسمح بقواعد Firestore مثل `allow read, write: if request.auth != null;` في الإنتاج. استخدم `firestore.rules` و`storage.rules` المرفقين.

## 4) تثبيت Cloud Functions

داخل `functions`:
```bash
npm install
```
ثم من جذر المشروع:
```bash
firebase login
firebase use <PROJECT_ID>
firebase deploy --only firestore:rules,storage,functions,hosting
```

## 5) إنشاء أول مدير

بعد إنشاء أول حساب، اعطه Claim `admin` بالطريقة الآمنة المناسبة للمشروع، ثم استخدم صفحة المستخدمين لإضافة مدراء آخرين عبر البريد.

## 6) الإشعارات

الواجهة تستخدم Firebase Cloud Messaging للـWeb Push، والطلبات الجديدة ترسل إشعاراً للسائقين المفعّلين. على الويب يجب أن يعمل الموقع عبر HTTPS، ويحتاج `firebase-messaging-sw.js` في جذر النطاق.

## 7) WebSocket / التحديث اللحظي

لم نضف WebSocket server منفصل. استخدمنا Firestore `onSnapshot` للتحديث اللحظي، وهو الأنسب مع بنية Firebase ويمنع المستخدم من الضغط على تحديث الصفحة كل مرة.

## 8) نموذج المحفظة

- العميل: يشحن الرصيد عند الحاجة. يجب أن يملك رصيداً قبل رفع الطلب.
- السائق: يدفع 10,000 جنيه مرة واحدة عند التفعيل، ثم يشحن المحفظة حسب حاجته.
- عند قبول السائق طلباً: يتم حجز 5% من قيمة الطلب من محفظته.
- عند إكمال الطلب بعد تأكيد العميل: العميل يدفع 100% من قيمة الطلب، السائق يحصل على 95%، والشركة تسجل 5% عمولة.
- السحب يمر بمراجعة الإدارة.

## 9) البيانات والخصوصية

العميل والسائق يرى كل منهما الاسم ورقم التواصل فقط. البريد الإلكتروني يبقى للإدارة. ملفات الهوية والإشعارات مخصصة للمراجعة الإدارية.

## 10) Netlify → APK

يمكنك نشر المشروع كـPWA على Netlify. بعد ذلك يمكنك تغليفه كتطبيق Android بواسطة Capacitor أو Trusted Web Activity، لكن قبل Google Play يجب إضافة حساب/حزمة Android، إعداد الأيقونة والشاشة الافتتاحية، وسياسة الخصوصية، واختبار الإشعارات والروابط.

## 11) WhatsApp OTP

لا تعتمد على WhatsApp الشخصي لإرسال أكواد تحقق. التحويل الصحيح يكون عبر WhatsApp Business Platform / Cloud API أو مزود رسمي. لذلك النسخة الحالية تستخدم رابط واتساب للتواصل، بينما التحقق من البريد يتم عبر Firebase Authentication، ويمكن لاحقاً إضافة WhatsApp OTP بخدمة رسمية.
