-- =====================================================
-- ИСПРАВЛЕНИЕ RLS ДЛЯ TRANSACTIONS
-- Проблема: Политика проверяет manager_id в company_branches,
-- но менеджеры теперь назначаются через таблицу branch_managers
-- =====================================================

-- 1. Удаляем старую политику вставки
DROP POLICY IF EXISTS "Managers can insert transactions" ON transactions;

-- 2. Создаем новую политику, которая проверяет ОБОИМИ способами:
--    - Старый способ: company_branches.manager_id (для обратной совместимости)
--    - Новый способ: через таблицу branch_managers
CREATE POLICY "Managers can insert transactions" 
ON transactions FOR INSERT 
TO authenticated 
WITH CHECK (
  -- Проверяем что пользователь - менеджер
  EXISTS (
    SELECT 1 FROM profiles 
    WHERE id = auth.uid() AND role = 'manager'
  )
  AND
  -- Проверяем что менеджер назначен на этот филиал (любым способом)
  (
    -- Новый способ: через branch_managers
    EXISTS (
      SELECT 1 FROM branch_managers 
      WHERE branch_id = transactions.branch_id 
        AND manager_id = auth.uid()
    )
    OR
    -- Старый способ: через company_branches.manager_id (fallback)
    EXISTS (
      SELECT 1 FROM company_branches 
      WHERE id = transactions.branch_id 
        AND manager_id = auth.uid()
    )
  )
);

-- 3. Также обновляем политику просмотра транзакций для менеджеров
DROP POLICY IF EXISTS "Managers can view their branch transactions" ON transactions;

CREATE POLICY "Managers can view their branch transactions" 
ON transactions FOR SELECT 
TO authenticated 
USING (
  -- Менеджер видит свои транзакции (те что он провел)
  manager_id = auth.uid() 
  OR 
  -- Или транзакции филиала, к которому он привязан (новый способ)
  EXISTS (
    SELECT 1 FROM branch_managers 
    WHERE branch_id = transactions.branch_id 
      AND manager_id = auth.uid()
  )
  OR
  -- Или старый способ через company_branches.manager_id
  branch_id IN (
    SELECT id FROM company_branches WHERE manager_id = auth.uid()
  )
);

-- =====================================================
-- ГОТОВО! Теперь менеджеры смогут создавать транзакции
-- =====================================================
