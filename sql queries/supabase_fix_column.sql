-- 1. Сначала создаем колонку (ОБЯЗАТЕЛЬНО)
ALTER TABLE company_branches 
ADD COLUMN IF NOT EXISTS map_priority int DEFAULT 3;

-- 2. Индекс для скорости
CREATE INDEX IF NOT EXISTS idx_company_branches_priority 
ON company_branches (map_priority);

-- 3. Пересоздаем функцию
DROP FUNCTION IF EXISTS get_branches_in_view;

CREATE OR REPLACE FUNCTION get_branches_in_view(
  min_lat float,
  max_lat float,
  min_lng float,
  max_lng float,
  zoom_level float
)
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
DECLARE
  target_priority int;
BEGIN
  IF zoom_level < 12 THEN
    target_priority := 1;
  ELSIF zoom_level < 15 THEN
    target_priority := 2;
  ELSE
    target_priority := 3;
  END IF;

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
      'name', c.name,
      'logo_url', c.logo_url,
      'description', c.description,
      'discount_percentage', c.discount_percentage
    ) as companies
  FROM company_branches b
  JOIN companies c ON b.company_id = c.id
  WHERE 
    b.latitude BETWEEN min_lat AND max_lat
    AND b.longitude BETWEEN min_lng AND max_lng
    AND b.map_priority <= target_priority;
END;
$$;

-- 4. Теперь можно обновлять приоритеты
-- UPDATE company_branches SET map_priority = 1 WHERE ...;
