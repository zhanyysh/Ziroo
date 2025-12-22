-- Включаем RLS для таблицы логов
ALTER TABLE admin_logs ENABLE ROW LEVEL SECURITY;

-- 1. Политика на ЧТЕНИЕ (SELECT)
-- Только админы могут смотреть историю действий
CREATE POLICY "Enable read access for admins" 
ON admin_logs FOR SELECT 
TO authenticated 
USING (
  (SELECT role FROM profiles WHERE id = auth.uid()) = 'admin'
);

-- 2. Политика на ДОБАВЛЕНИЕ (INSERT)
-- Только админы могут записывать действия
CREATE POLICY "Enable insert for admins" 
ON admin_logs FOR INSERT 
TO authenticated 
WITH CHECK (
  (SELECT role FROM profiles WHERE id = auth.uid()) = 'admin'
);

-- На всякий случай, если вы еще не добавили политики для таблицы companies (чтобы список компаний работал)
ALTER TABLE companies ENABLE ROW LEVEL SECURITY;

-- Компании видят все (для пользователей)
CREATE POLICY "Enable read access for all" 
ON companies FOR SELECT 
TO authenticated 
USING (true);

-- Создавать/Редактировать/Удалять компании могут только админы
CREATE POLICY "Enable all access for admins" 
ON companies FOR ALL 
TO authenticated 
USING (
  (SELECT role FROM profiles WHERE id = auth.uid()) = 'admin'
)
WITH CHECK (
  (SELECT role FROM profiles WHERE id = auth.uid()) = 'admin'
);
