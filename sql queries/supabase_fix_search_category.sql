-- 1. Исправляем функцию поиска (rpcSearch)
-- Сначала удаляем старую функцию, так как меняется возвращаемый тип (structure)
DROP FUNCTION IF EXISTS search_branches(text, float, float);

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
      'category', c.category,
      'discount_percentage', c.discount_percentage
    ) as companies
  FROM company_branches b
  JOIN companies c ON b.company_id = c.id
  WHERE 
    c.name ILIKE '%' || query_text || '%' 
    OR b.name ILIKE '%' || query_text || '%'
    OR c.description ILIKE '%' || query_text || '%'
    OR c.category ILIKE '%' || query_text || '%'
  LIMIT 50;
END;
$$;

-- 2. Исправляем функцию получения объектов в области видимости (get_branches_in_view)
-- Чтобы тег "Еда" и т.д. был доступен в UI при обычном просмотре карты
DROP FUNCTION IF EXISTS get_branches_in_view(float, float, float, float, float);

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
  -- Логика LOD
  IF zoom_level < 12 THEN target_priority := 1;
  ELSIF zoom_level < 15 THEN target_priority := 2;
  ELSE target_priority := 3;
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
      'category', c.category,
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
