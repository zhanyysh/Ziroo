-- Add full_name column to profiles table
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS full_name TEXT;

-- Update existing profiles with name from auth.users (this is a best-effort one-time migration)
-- Note: We cannot easily access auth.users metadata from here in a simple query without specific permissions or functions,
-- so we will just add the column. The app will handle the fallback.
