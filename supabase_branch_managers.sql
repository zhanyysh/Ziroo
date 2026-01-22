-- =====================================================
-- Таблица для назначения нескольких менеджеров на филиал
-- Many-to-Many связь: branch <-> manager
-- =====================================================

-- 1. Создаем связующую таблицу
CREATE TABLE IF NOT EXISTS branch_managers (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  branch_id uuid NOT NULL REFERENCES company_branches(id) ON DELETE CASCADE,
  manager_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  assigned_at timestamptz DEFAULT now(),
  assigned_by uuid REFERENCES profiles(id), -- Кто назначил (админ)
  
  -- Уникальная пара: один менеджер на один филиал только один раз
  UNIQUE(branch_id, manager_id)
);

-- 2. Индексы для быстрого поиска
CREATE INDEX IF NOT EXISTS idx_branch_managers_branch ON branch_managers(branch_id);
CREATE INDEX IF NOT EXISTS idx_branch_managers_manager ON branch_managers(manager_id);

-- 3. RLS политики
ALTER TABLE branch_managers ENABLE ROW LEVEL SECURITY;

-- Все могут читать (для проверки назначения)
CREATE POLICY "Allow read for authenticated" ON branch_managers
  FOR SELECT TO authenticated USING (true);

-- Только админы могут добавлять/удалять
CREATE POLICY "Allow insert for admins" ON branch_managers
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin')
  );

CREATE POLICY "Allow delete for admins" ON branch_managers
  FOR DELETE TO authenticated
  USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin')
  );

-- 4. Функция для получения филиала менеджера (возвращает первый назначенный)
CREATE OR REPLACE FUNCTION get_manager_branch(p_manager_id uuid)
RETURNS TABLE (
  id uuid,
  company_id uuid,
  name text,
  latitude float,
  longitude float,
  address text,
  phone text,
  working_hours text,
  is_vip boolean,
  map_priority int,
  companies json
)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    b.id,
    b.company_id,
    b.name,
    b.latitude,
    b.longitude,
    b.address,
    b.phone,
    b.working_hours,
    b.is_vip,
    b.map_priority,
    json_build_object(
      'id', c.id,
      'name', c.name,
      'logo_url', c.logo_url,
      'description', c.description,
      'discount_percentage', c.discount_percentage,
      'category', c.category
    ) as companies
  FROM branch_managers bm
  JOIN company_branches b ON bm.branch_id = b.id
  JOIN companies c ON b.company_id = c.id
  WHERE bm.manager_id = p_manager_id
  ORDER BY bm.assigned_at ASC
  LIMIT 1;
END;
$$;

-- 5. Функция для получения всех филиалов менеджера
CREATE OR REPLACE FUNCTION get_manager_branches(p_manager_id uuid)
RETURNS TABLE (
  id uuid,
  company_id uuid,
  name text,
  latitude float,
  longitude float,
  address text,
  phone text,
  working_hours text,
  is_vip boolean,
  map_priority int,
  companies json
)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    b.id,
    b.company_id,
    b.name,
    b.latitude,
    b.longitude,
    b.address,
    b.phone,
    b.working_hours,
    b.is_vip,
    b.map_priority,
    json_build_object(
      'id', c.id,
      'name', c.name,
      'logo_url', c.logo_url,
      'description', c.description,
      'discount_percentage', c.discount_percentage,
      'category', c.category
    ) as companies
  FROM branch_managers bm
  JOIN company_branches b ON bm.branch_id = b.id
  JOIN companies c ON b.company_id = c.id
  WHERE bm.manager_id = p_manager_id
  ORDER BY bm.assigned_at ASC;
END;
$$;

-- 6. Миграция существующих данных (если manager_id уже был заполнен)
INSERT INTO branch_managers (branch_id, manager_id)
SELECT id, manager_id FROM company_branches 
WHERE manager_id IS NOT NULL
ON CONFLICT (branch_id, manager_id) DO NOTHING;

-- 7. (Опционально) Можно удалить старую колонку manager_id из company_branches
-- ALTER TABLE company_branches DROP COLUMN manager_id;
-- НО лучше оставить для обратной совместимости

SELECT 'Migration complete. Branch managers table created.' as status;
