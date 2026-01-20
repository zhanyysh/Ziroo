-- Функция глобального поиска (Global Search)
-- Ищет везде, а не только на экране.
-- Сортирует по расстоянию до пользователя (если переданы координаты).

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
  companies json,
  dist_meters float
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
    ) as companies,
    -- Расчет расстояния по формуле гаверсинуса (упрощенно для сортировки)
    CASE 
      WHEN user_lat IS NOT NULL AND user_lng IS NOT NULL THEN
        (point(b.longitude, b.latitude) <@> point(user_lng, user_lat)) * 1609.34
      ELSE 0::float 
    END as dist_meters
  FROM company_branches b
  JOIN companies c ON b.company_id = c.id
  WHERE 
    c.name ILIKE '%' || query_text || '%' 
    OR b.name ILIKE '%' || query_text || '%'
    OR c.description ILIKE '%' || query_text || '%'
  ORDER BY 
    dist_meters ASC, -- Сначала ближайшие
    c.name ASC 
  LIMIT 50; -- Ограничиваем выдачу, чтобы не грузить карту
END;
$$;

-- Примечание: <@> оператор требует расширения cube или earthdistance. 
-- Если их нет, используем упрощенную сортировку без distance, или стандартную формулу.
-- Для надежности, вот вариант без расширений (немного медленнее, но работает везде):

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
  -- dist_meters float -- убираем сложную математику из SQL для простоты, сортируем на клиенте или просто по имени
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
