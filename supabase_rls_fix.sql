-- Включить RLS для таблицы (если еще не включено)
ALTER TABLE company_branches ENABLE ROW LEVEL SECURITY;

-- 1. Политика на ЧТЕНИЕ (SELECT)
-- Разрешаем всем авторизованным пользователям видеть филиалы
CREATE POLICY "Enable read access for authenticated users" 
ON company_branches FOR SELECT 
TO authenticated 
USING (true);

-- 2. Политика на ДОБАВЛЕНИЕ (INSERT)
-- Разрешаем добавлять только если в таблице profiles у пользователя роль 'admin'
CREATE POLICY "Enable insert for admins only" 
ON company_branches FOR INSERT 
TO authenticated 
WITH CHECK (
  (SELECT role FROM profiles WHERE id = auth.uid()) = 'admin'
);

-- 3. Политика на ОБНОВЛЕНИЕ (UPDATE)
CREATE POLICY "Enable update for admins only" 
ON company_branches FOR UPDATE 
TO authenticated 
USING (
  (SELECT role FROM profiles WHERE id = auth.uid()) = 'admin'
)
WITH CHECK (
  (SELECT role FROM profiles WHERE id = auth.uid()) = 'admin'
);

-- 4. Политика на УДАЛЕНИЕ (DELETE)
CREATE POLICY "Enable delete for admins only" 
ON company_branches FOR DELETE 
TO authenticated 
USING (
  (SELECT role FROM profiles WHERE id = auth.uid()) = 'admin'
);

-- ВАЖНО: Убедитесь, что таблица profiles доступна для чтения!
-- Если для profiles тоже включен RLS, добавьте политику чтения:
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Enable read access for profiles" 
ON profiles FOR SELECT 
TO authenticated 
USING (true);
