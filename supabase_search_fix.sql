-- Исправление 1: Проверяем и добавляем отсутствующие колонки, если их нет
ALTER TABLE company_branches 
ADD COLUMN IF NOT EXISTS phone text,
ADD COLUMN IF NOT EXISTS working_hours text;

-- Исправление 2: Функция поиска БЕЗ дублирования имен колонок и с правильной сигнатурой
-- Важно: мы удаляем старую версию, чтобы не было конфликтов версий функции
DROP FUNCTION IF EXISTS search_branches;

CREATE OR REPLACE FUNCTION search_branches(
  query_text text,
  user_lat float DEFAULT NULL,
  user_lng float DEFAULT NULL
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
      'name', c.name,
      'logo_url', c.logo_url,
      'description', c.description,
      'discount_percentage', c.discount_percentage
    ) as companies
  FROM company_branches b
  JOIN companies c ON b.company_id = c.id
  WHERE 
    c.name ILIKE '%' || query_text || '%' 
    OR b.name ILIKE '%' || query_text || '%'
    OR c.description ILIKE '%' || query_text || '%'
  LIMIT 50;
END;
$$;
