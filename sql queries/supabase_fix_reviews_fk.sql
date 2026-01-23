-- Fix relationship between branch_reviews and profiles
-- This is necessary for the query .select('*, profiles:user_id(...)') to work

-- 1. Ensure profiles table exists (idempotent)
CREATE TABLE IF NOT EXISTS profiles (
  id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
  email TEXT,
  avatar_url TEXT,
  role TEXT DEFAULT 'user',
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 2. Fix branch_reviews foreign key
DO $$
BEGIN
    -- Try to drop the constraint if it exists (handling potential naming variations)
    IF EXISTS (SELECT 1 FROM information_schema.table_constraints WHERE constraint_name = 'branch_reviews_user_id_fkey') THEN
        ALTER TABLE branch_reviews DROP CONSTRAINT branch_reviews_user_id_fkey;
    END IF;
END $$;

-- 3. Add the correct foreign key to profiles
ALTER TABLE branch_reviews
ADD CONSTRAINT branch_reviews_user_id_fkey
FOREIGN KEY (user_id)
REFERENCES profiles(id)
ON DELETE CASCADE;

-- 4. Refresh schema cache (usually automatic, but good to note)
NOTIFY pgrst, 'reload config';
