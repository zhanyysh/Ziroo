-- Add category column to companies table
ALTER TABLE public.companies 
ADD COLUMN IF NOT EXISTS category text DEFAULT 'Другое';
