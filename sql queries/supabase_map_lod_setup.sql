-- 1. Добавляем колонку приоритета отображения (LOD)
ALTER TABLE company_branches 
ADD COLUMN IF NOT EXISTS map_priority int DEFAULT 3;

-- 2. Создаем индексы
CREATE INDEX IF NOT EXISTS idx_company_branches_priority 
ON company_branches (map_priority);

CREATE INDEX IF NOT EXISTS idx_company_branches_coords 
ON company_branches (latitude, longitude);

-- 3. Функция RPC для получения объектов в видимой области (Bounding Box) с учетом зума
-- Возвращает структуру, совместимую с Dart-моделью (companies как json объект)
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
  -- Логика LOD (Level of Detail)
  IF zoom_level < 12 THEN
    target_priority := 1; -- Только крупные
  ELSIF zoom_level < 15 THEN
    target_priority := 2; -- Крупные + Средние
  ELSE
    target_priority := 3; -- Все
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

-- 4. ПРИМЕРЫ ОБНОВЛЕНИЯ ДАННЫХ
-- UPDATE company_branches b SET map_priority = 1 FROM companies c WHERE b.company_id = c.id AND c.name ILIKE '%Mall%';
