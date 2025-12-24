-- 1. Fix Storage Permissions for 'avatars' bucket
-- Enable RLS on storage.objects if not already enabled (it usually is)
-- ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;

-- Allow authenticated users to upload files to 'avatars' bucket
DROP POLICY IF EXISTS "Allow authenticated uploads" ON storage.objects;
CREATE POLICY "Allow authenticated uploads"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK ( bucket_id = 'avatars' );

-- Allow authenticated users to update their files
DROP POLICY IF EXISTS "Allow authenticated updates" ON storage.objects;
CREATE POLICY "Allow authenticated updates"
ON storage.objects FOR UPDATE
TO authenticated
USING ( bucket_id = 'avatars' );

-- Allow public read access to avatars
DROP POLICY IF EXISTS "Allow public read" ON storage.objects;
CREATE POLICY "Allow public read"
ON storage.objects FOR SELECT
USING ( bucket_id = 'avatars' );

-- Allow users to delete their own files
DROP POLICY IF EXISTS "Allow authenticated deletes" ON storage.objects;
CREATE POLICY "Allow authenticated deletes"
ON storage.objects FOR DELETE
TO authenticated
USING ( bucket_id = 'avatars' AND auth.uid()::text = (storage.foldername(name))[1] ); 
-- Note: The delete policy above assumes a folder structure or naming convention, 
-- but for now, let's just allow delete if they own it (which is hard to track without metadata).
-- Simpler delete policy for this project:
DROP POLICY IF EXISTS "Allow users to delete own avatars" ON storage.objects;
CREATE POLICY "Allow users to delete own avatars"
ON storage.objects FOR DELETE
TO authenticated
USING ( bucket_id = 'avatars' AND owner = auth.uid() );


-- 2. Backfill profiles for existing users
-- This ensures that users created before the trigger was added still have a profile
INSERT INTO public.profiles (id, email, role)
SELECT id, email, 'user'
FROM auth.users
WHERE id NOT IN (SELECT id FROM public.profiles);

-- 3. Ensure branch_reviews has a unique constraint if we want one review per user per branch
-- (Optional, based on requirement. If "comments", multiple are fine. If "reviews", usually one.)
-- Let's leave it as multiple comments for now as requested "like comments".

