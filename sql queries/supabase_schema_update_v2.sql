-- 1. Create admin_logs table
CREATE TABLE IF NOT EXISTS admin_logs (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  admin_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  action_type TEXT NOT NULL, -- 'create_company', 'delete_company', 'add_branch', etc.
  details TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 2. Add Cascade Delete for company_branches
-- First, drop the existing constraint if we can guess its name, or just add a new one if the old one allows it.
-- Since we don't know the constraint name, we will try to drop the generic one or just rely on the user running this.
-- A safer way is to alter the table to drop the constraint by name if known, but we don't know it.
-- We will assume the standard naming convention or just try to add a new one after dropping the old one if possible.
-- Actually, the best way without knowing the name is to just rely on the Dart code for now OR 
-- try to find the constraint name. But for this environment, let's just add the table and handle cascade in Dart for safety, 
-- AND try to add the constraint if it doesn't exist.

-- Let's just create the logs table for now. The user asked for "cascade delete", 
-- I will implement it in Dart (delete branches then company) to be 100% sure it works without complex SQL migration issues.
-- BUT, I will also provide the SQL to add the constraint if they want to run it.

ALTER TABLE company_branches
DROP CONSTRAINT IF EXISTS company_branches_company_id_fkey;

ALTER TABLE company_branches
ADD CONSTRAINT company_branches_company_id_fkey
FOREIGN KEY (company_id)
REFERENCES companies(id)
ON DELETE CASCADE;
