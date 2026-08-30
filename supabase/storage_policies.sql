-- ============================================================================
-- Supabase Storage Policies for jwan-files bucket
-- ============================================================================
-- These policies control who can upload, read, and delete files
-- Apply these policies in Supabase Dashboard: Storage > jwan-files > Policies
-- ============================================================================

-- Policy 1: Users can read their own identity documents
-- Path: users/{user_id}/identity/*
CREATE POLICY "users_read_own_identity"
ON storage.objects
FOR SELECT
USING (
  bucket_id = 'jwan-files' AND
  (auth.uid() = (storage.foldername(name))[1] OR
   (SELECT role FROM public.users WHERE uid = auth.uid() LIMIT 1) = 'admin')
);

-- Policy 2: Users can read their own driver documents
-- Path: users/{user_id}/driver/*
CREATE POLICY "users_read_own_driver_docs"
ON storage.objects
FOR SELECT
USING (
  bucket_id = 'jwan-files' AND
  (auth.uid() = (storage.foldername(name))[1] OR
   (SELECT role FROM public.users WHERE uid = auth.uid() LIMIT 1) = 'admin')
);

-- Policy 3: Users can read their own receipts
-- Path: receipts/{user_id}/*
CREATE POLICY "users_read_own_receipts"
ON storage.objects
FOR SELECT
USING (
  bucket_id = 'jwan-files' AND
  (auth.uid() = (storage.foldername(name))[1] OR
   (SELECT role FROM public.users WHERE uid = auth.uid() LIMIT 1) = 'admin')
);

-- Policy 4: Admin can read all files
CREATE POLICY "admin_read_all_files"
ON storage.objects
FOR SELECT
USING (
  bucket_id = 'jwan-files' AND
  (SELECT role FROM public.users WHERE uid = auth.uid() LIMIT 1) = 'admin'
);

-- Policy 5: Users can upload to their own identity directory
-- Path: users/{user_id}/identity/*
-- Max 10MB, image or PDF only
CREATE POLICY "users_upload_own_identity"
ON storage.objects
FOR INSERT
WITH CHECK (
  bucket_id = 'jwan-files' AND
  auth.uid() = (storage.foldername(name))[1] AND
  storage.filename(name) LIKE 'identity/%' AND
  (storage.foldername(name))[2] = 'identity' AND
  storage.foldername(name)[3] IS NULL AND
  storage.extension(name) IN ('jpg', 'jpeg', 'png', 'webp', 'pdf') AND
  (storage.size(name) IS NULL OR storage.size(name) < 10485760)
);

-- Policy 6: Users can upload to their own driver directory
-- Path: users/{user_id}/driver/*
-- Max 10MB, image or PDF only
CREATE POLICY "users_upload_own_driver_docs"
ON storage.objects
FOR INSERT
WITH CHECK (
  bucket_id = 'jwan-files' AND
  auth.uid() = (storage.foldername(name))[1] AND
  (
    storage.filename(name) LIKE 'driver/%' OR
    storage.filename(name) LIKE 'owner_proof/%' OR
    storage.filename(name) LIKE 'sticker/%'
  ) AND
  storage.extension(name) IN ('jpg', 'jpeg', 'png', 'webp', 'pdf') AND
  (storage.size(name) IS NULL OR storage.size(name) < 10485760)
);

-- Policy 7: Users can upload receipts for topups
-- Path: receipts/{user_id}/*
-- Max 10MB, image only
CREATE POLICY "users_upload_receipts"
ON storage.objects
FOR INSERT
WITH CHECK (
  bucket_id = 'jwan-files' AND
  auth.uid() = (storage.foldername(name))[1] AND
  storage.filename(name) LIKE 'receipts/%' AND
  storage.extension(name) IN ('jpg', 'jpeg', 'png', 'webp') AND
  (storage.size(name) IS NULL OR storage.size(name) < 10485760)
);

-- Policy 8: Users can update their own files (replace with new version)
CREATE POLICY "users_update_own_files"
ON storage.objects
FOR UPDATE
USING (
  bucket_id = 'jwan-files' AND
  auth.uid() = (storage.foldername(name))[1]
);

-- Policy 9: Admin can upload files (for testing or manual fixes)
CREATE POLICY "admin_upload_files"
ON storage.objects
FOR INSERT
WITH CHECK (
  bucket_id = 'jwan-files' AND
  (SELECT role FROM public.users WHERE uid = auth.uid() LIMIT 1) = 'admin'
);

-- Policy 10: Users can delete their own files
CREATE POLICY "users_delete_own_files"
ON storage.objects
FOR DELETE
USING (
  bucket_id = 'jwan-files' AND
  auth.uid() = (storage.foldername(name))[1]
);

-- Policy 11: Admin can delete any file
CREATE POLICY "admin_delete_files"
ON storage.objects
FOR DELETE
USING (
  bucket_id = 'jwan-files' AND
  (SELECT role FROM public.users WHERE uid = auth.uid() LIMIT 1) = 'admin'
);
