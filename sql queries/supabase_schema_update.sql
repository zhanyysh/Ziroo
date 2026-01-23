-- Run this command in your Supabase SQL Editor to add the missing column
ALTER TABLE company_branches ADD COLUMN is_vip BOOLEAN DEFAULT FALSE;