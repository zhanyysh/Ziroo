-- =====================================================
-- MANAGER FUNCTIONALITY SETUP
-- Run this in Supabase SQL Editor
-- =====================================================

-- 1. Add manager_id to company_branches
ALTER TABLE company_branches 
ADD COLUMN IF NOT EXISTS manager_id UUID REFERENCES auth.users(id) ON DELETE SET NULL;

-- 2. Create transactions table
CREATE TABLE IF NOT EXISTS transactions (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
  
  -- Who made the purchase
  customer_id UUID REFERENCES auth.users(id) ON DELETE SET NULL NOT NULL,
  
  -- Where the purchase was made
  branch_id UUID REFERENCES company_branches(id) ON DELETE CASCADE NOT NULL,
  company_id UUID REFERENCES companies(id) ON DELETE CASCADE NOT NULL,
  
  -- Who processed the transaction (manager)
  manager_id UUID REFERENCES auth.users(id) ON DELETE SET NULL NOT NULL,
  
  -- Financial data
  original_amount DECIMAL(10,2) NOT NULL,   -- Amount before discount
  discount_percent INTEGER NOT NULL,         -- Discount percentage
  discount_amount DECIMAL(10,2) NOT NULL,    -- Discount amount
  final_amount DECIMAL(10,2) NOT NULL        -- Final amount to pay
);

-- 3. Create index for faster queries
CREATE INDEX IF NOT EXISTS idx_transactions_customer ON transactions(customer_id);
CREATE INDEX IF NOT EXISTS idx_transactions_branch ON transactions(branch_id);
CREATE INDEX IF NOT EXISTS idx_transactions_manager ON transactions(manager_id);
CREATE INDEX IF NOT EXISTS idx_transactions_created ON transactions(created_at DESC);

-- 4. Enable RLS
ALTER TABLE transactions ENABLE ROW LEVEL SECURITY;

-- 5. RLS Policies for transactions

-- Managers can view transactions from their branch
CREATE POLICY "Managers can view their branch transactions" 
ON transactions FOR SELECT 
TO authenticated 
USING (
  manager_id = auth.uid() 
  OR 
  branch_id IN (
    SELECT id FROM company_branches WHERE manager_id = auth.uid()
  )
);

-- Managers can insert transactions for their branch
CREATE POLICY "Managers can insert transactions" 
ON transactions FOR INSERT 
TO authenticated 
WITH CHECK (
  EXISTS (
    SELECT 1 FROM company_branches 
    WHERE id = branch_id AND manager_id = auth.uid()
  )
  AND
  EXISTS (
    SELECT 1 FROM profiles 
    WHERE id = auth.uid() AND role = 'manager'
  )
);

-- Customers can view their own transactions
CREATE POLICY "Customers can view their own transactions" 
ON transactions FOR SELECT 
TO authenticated 
USING (customer_id = auth.uid());

-- Admins can view all transactions
CREATE POLICY "Admins can view all transactions" 
ON transactions FOR SELECT 
TO authenticated 
USING (
  EXISTS (
    SELECT 1 FROM profiles 
    WHERE id = auth.uid() AND role = 'admin'
  )
);

-- 6. Policy for company_branches - managers can view their assigned branch
CREATE POLICY "Managers can view their branch" 
ON company_branches FOR SELECT 
TO authenticated 
USING (
  manager_id = auth.uid() 
  OR 
  EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('admin', 'user'))
);

-- =====================================================
-- DONE! Now managers can:
-- 1. Be assigned to a branch (manager_id in company_branches)
-- 2. Create transactions for customers
-- 3. View transactions from their branch
-- =====================================================
