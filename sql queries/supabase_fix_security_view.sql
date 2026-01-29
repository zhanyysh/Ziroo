-- ============================================
-- Исправление безопасности: удаление небезопасного VIEW
-- ============================================
-- Проблема: VIEW user_full_profile раскрывает данные auth.users
-- и использует SECURITY DEFINER, обходя RLS
-- ============================================

-- Удаляем небезопасный VIEW
DROP VIEW IF EXISTS public.user_full_profile;

-- ============================================
-- Если нужен VIEW для профиля текущего пользователя,
-- используйте функцию вместо VIEW:
-- ============================================

-- Безопасная функция для получения профиля ТОЛЬКО текущего пользователя
CREATE OR REPLACE FUNCTION public.get_my_profile()
RETURNS TABLE (
  id UUID,
  email TEXT,
  phone TEXT,
  full_name TEXT,
  avatar_url TEXT,
  role TEXT,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ
) 
LANGUAGE plpgsql
SECURITY INVOKER  -- Выполняется с правами ВЫЗЫВАЮЩЕГО, не создателя
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    p.id,
    p.email,
    p.phone,
    p.full_name,
    p.avatar_url,
    p.role,
    p.created_at,
    p.updated_at
  FROM public.profiles p
  WHERE p.id = auth.uid();  -- Только свои данные!
END;
$$;

-- Разрешаем вызов только аутентифицированным пользователям
REVOKE ALL ON FUNCTION public.get_my_profile() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_my_profile() FROM anon;
GRANT EXECUTE ON FUNCTION public.get_my_profile() TO authenticated;


-- ============================================
-- ИНСТРУКЦИЯ:
-- ============================================
-- 1. Выполните этот скрипт в Supabase SQL Editor
-- 2. Ошибки безопасности исчезнут
-- 
-- Использование функции в приложении (если нужно):
-- SELECT * FROM get_my_profile();
-- ============================================
