-- Оптимизация поиска с использованием pg_trgm (Trigrams)
-- 1. Включаем расширение для нечеткого поиска и ускорения LIKE запросов
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- 2. Создаем GIN индексы для ускорения ILIKE '%...%'
-- Это критически важно для производительности: вместо seq scan будет использоваться bitmap index scan
CREATE INDEX IF NOT EXISTS idx_companies_name_trgm ON companies USING gin (name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_companies_desc_trgm ON companies USING gin (description gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_companies_category_trgm ON companies USING gin (category gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_branches_name_trgm ON company_branches USING gin (name gin_trgm_ops);

-- 3. Функция глобального поиска (Global Search)
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
DECLARE
    clean_query text;
BEGIN
  -- Очистка запроса
  clean_query := trim(query_text);

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
      'discount_percentage', c.discount_percentage,
      'category', c.category
    ) as companies,
    -- Расчет расстояния
    CASE 
      WHEN user_lat IS NOT NULL AND user_lng IS NOT NULL THEN
        (sqrt(power(b.latitude - user_lat, 2) + power(b.longitude - user_lng, 2)) * 111000)::float
      ELSE 0::float 
    END as dist_meters
  FROM company_branches b
  JOIN companies c ON b.company_id = c.id
  WHERE 
    -- Поиск по названию, описанию И КАТЕГОРИИ
    c.name ILIKE '%' || clean_query || '%' 
    OR b.name ILIKE '%' || clean_query || '%'
    OR c.description ILIKE '%' || clean_query || '%'
    OR c.category ILIKE '%' || clean_query || '%'
  ORDER BY 
    -- Если пользователь ввел слово "еда", и это категория - приоритет выше
    (CASE WHEN c.category ILIKE clean_query THEN 0 ELSE 1 END) ASC,
    -- Затем совпадение по имени
    (CASE WHEN c.name ILIKE clean_query || '%' THEN 0 ELSE 1 END) ASC,
    -- Затем расстояние
    dist_meters ASC
  LIMIT 50; 
END;
$$;
