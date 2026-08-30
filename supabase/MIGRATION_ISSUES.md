# 🔍 تقرير مراجعة المرحلة الأولى - Supabase Schema

## ⚠️ المشاكل المكتشفة والتحديثات المطلوبة

### 1️⃣ مشكلة ربط Firebase UID مع Supabase Auth

**المشكلة الحالية:**
- Schema استخدم `uid TEXT` لتخزين Firebase UID
- لكن `auth.uid()` في Supabase يعطي UUID من جدول `auth.users`
- هناك عدم توافق بين النوعين

**الحل المقترح:**
```
خيار أ: إنشاء جدول migration يربط Firebase UID مع Supabase UUID
  firebase_uid (TEXT) → supabase_uid (UUID)

خيار ب: استخدام Firebase UID الأصلي كـ uid TEXT مباشرة
  - لكن يجب إضافة trigger عند إنشاء auth user
  - عند login، نتحقق من وجود المستخدم في جدول users
  - إذا لم يكن موجود، ننشئه تلقائيًا

الخيار الموصى به: خيار ب (لأن المستخدمين حاليًا عندهم Firebase UID)
```

**ما يجب تصحيحه في schema:**
- إضافة `trigger` يراقب `auth.users` جدول
- عند `auth.users.insert`، ننشئ سجل في `public.users` تلقائيًا
- حفظ Firebase UID في `users.uid` للمرجعية

---

### 2️⃣ مشكلة RLS Policies وpermissions

**المشكلة:**
- بعض policies تستخدم `auth.uid()` الذي يكون TEXT
- لكن Supabase `auth.uid()` يرجع UUID
- هناك عدم توافق في المقارنة

**التصحيح:**
```sql
-- ✗ WRONG (current)
WHERE auth.uid() = uid  -- UUID = TEXT

-- ✓ CORRECT
WHERE auth.uid()::text = uid  -- UUID::text = TEXT
```

---

### 3️⃣ مشكلة جدول `user_tokens`

**المشكلة:**
- `user_tokens` لديه `user_id TEXT UNIQUE NOT NULL`
- لكن المستخدم الواحد قد يكون عنده عدة tokens (متصفحات/أجهزة مختلفة)
- UNIQUE يسبب مشكلة

**التصحيح:**
```sql
-- إزالة UNIQUE constraint
-- استخدام composite key بدلاً منه
CREATE TABLE public.user_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL,
  token TEXT NOT NULL UNIQUE,  -- Token نفسه يجب يكون unique
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(user_id, token)  -- أو هكذا
);
```

---

### 4️⃣ مشكلة Ratings Policy

**المشكلة:**
- ratings policy تسمح بـ INSERT فقط للـ admin
- لكن في `index.html` الكود يسمح للعميل بتقييم الخدمة مباشرة
- هناك تضارب

**الحل:**
```sql
-- يجب أن يكون العميل قادر على إنشاء rating
-- لكن يمكنه فقط تقييم الطلبات الخاصة به

CREATE POLICY "ratings_create_customer"
ON public.ratings FOR INSERT
WITH CHECK (
  auth.uid()::text = customer_id AND
  EXISTS (SELECT 1 FROM orders WHERE id = order_id AND status = 'completed')
);
```

---

### 5️⃣ مشكلة Functions و SECURITY DEFINER

**المشكلة:**
```sql
-- في الدالة:
IF auth.role() != 'authenticated' OR ... THEN
```
- `auth.role()` في Supabase يرجع 'authenticated' أو 'anon'
- لكن الشرط يستخدم admin check - هذا غير صحيح

**التصحيح:**
```sql
-- يجب استخدام SECURITY DEFINER بشكل صحيح
-- والتحقق من أن المستخدم هو admin من جدول users

CREATE OR REPLACE FUNCTION public.add_wallet_transaction(...)
RETURNS TABLE(success BOOLEAN, message TEXT, new_balance NUMERIC)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_uid TEXT := auth.uid()::text;
  v_caller_role TEXT;
BEGIN
  -- التحقق من أن المستدعي هو admin
  SELECT role INTO v_caller_role FROM public.users 
  WHERE uid = v_caller_uid LIMIT 1;
  
  IF v_caller_role != 'admin' THEN
    RETURN QUERY SELECT FALSE, 'Unauthorized'::TEXT, 0::NUMERIC;
    RETURN;
  END IF;
  
  -- المنطق هنا...
END;
$$;
```

---

### 6️⃣ مشكلة في order_comments policy

**المشكلة:**
- Policy تتحقق من `auth.uid()` مقابل `customer_id` (TEXT)
- لكن ليس هناك تحويل من UUID إلى TEXT

**التصحيح:**
```sql
CREATE POLICY "order_comments_read_involved"
ON public.order_comments FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM public.orders o 
    WHERE o.id = order_id 
    AND (o.customer_id = auth.uid()::text OR o.driver_id = auth.uid()::text)
  )
  OR (SELECT role FROM public.users WHERE uid = auth.uid()::text LIMIT 1) = 'admin'
);
```

---

### 7️⃣ جدول `order_price_events` موجود؟

**المراجعة من الكود:**
```javascript
// في index.html (سطر 28)
exports.notifyPricedOrder=onDocumentCreated('orderPriceEvents/{eventId}',...

// في firebase.json
```

✅ **نعم، موجود في المشروع** - Schema يتضمنه بشكل صحيح

---

### 8️⃣ Transactions Immutability

**المشكلة:**
- `transactions` جدول يجب أن يكون immutable (لا update، لا delete)
- Schema بيحقق هذا بشكل صحيح ✅

---

### 9️⃣ Storage Policies - مسارات الملفات

**المراجعة من الكود في index.html:**

```javascript
// Line 84: uploadFile function
const ok=['image/jpeg','image/png','image/webp','application/pdf'];

// Line 127: Identity upload
// Line 123: Sticker upload  
// Line 122: Owner proof upload
```

**المسارات المستخدمة فعليًا:**
```
users/{uid}/identity/{filename}
users/{uid}/driver/{filename}
users/{uid}/{sticker/owner_proof}
receipts/{uid}/{filename}
```

✅ **Storage policies غطيت هذا بشكل صحيح**

---

### 🔟 مشكلة في RLS - subqueries متكررة

**المشكلة:**
```sql
-- هذا inefficient جداً
WHERE (SELECT role FROM public.users WHERE uid = auth.uid() LIMIT 1) = 'admin'
```

**الحل:**
استخدام custom function أو JWT claims (إن أمكن)

```sql
-- أفضل طريقة: استخدام JWT custom claims
-- عند إنشاء user كـ admin، نضيف claim في Firebase/Supabase
-- ثم نستخدمه مباشرة

WHERE auth.jwt() ->> 'user_role' = 'admin'
```

---

## 📋 ملخص التصحيحات المطلوبة

### قبل تنفيذ SQL على Supabase:

1. **✏️ تصحيح جميع `auth.uid()` إلى `auth.uid()::text`**
2. **✏️ تصحيح جدول `user_tokens` (إزالة UNIQUE على user_id)**
3. **✏️ تصحيح RLS Ratings (السماح للعميل بـ INSERT)**
4. **✏️ تصحيح Functions للتحقق من admin بشكل صحيح**
5. **✏️ إضافة trigger لـ auth.users لإنشاء users تلقائيًا**
6. **✏️ استخدام JWT claims للـ admin role (اختياري لكن موصى به)**
7. **✏️ إضافة index لـ `user_id` في `user_tokens` للبحث السريع**

---

## 🎯 الخطوة التالية

**أريد موافقتك على:**

1. هل نستخدم Firebase UID كـ `uid TEXT` ونربطه مع Supabase Auth؟
   - ✅ نعم → أضيف trigger للربط التلقائي
   - ❌ لا → نبدأ من الصفر مع Supabase Auth UUIDs

2. هل نستخدم JWT custom claims للـ admin role؟
   - ✅ نعم → أبسط وأسرع في RLS
   - ❌ لا → نكمل مع subqueries

3. هل تريد أصحح schema الآن؟

---

## 📊 حالة الملفات

```
supabase/
├── schema.sql ✅ (موجود - يحتاج تصحيحات)
├── storage_policies.sql ✅ (موجود)
└── MIGRATION_ISSUES.md (هذا الملف)

Firebase/ (لم تُلمس - محفوظة)
├── functions/
├── firestore.rules
├── storage.rules
└── ... (كل ملفات Firebase الأصلية)

index.html ✅ (لم يتغير)
```
