-- ============================================
-- Синхронизация auth.users → profiles
-- ============================================
-- Этот скрипт создаёт триггеры для автоматической
-- синхронизации данных из auth.users в profiles
-- ============================================

-- 1. Функция синхронизации при СОЗДАНИИ пользователя
-- (улучшенная версия handle_new_user)
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (
    id,
    email,
    phone,
    full_name,
    avatar_url,
    role,
    created_at,
    updated_at
  ) VALUES (
    NEW.id,
    NEW.email,
    NEW.phone,
    COALESCE(
      NEW.raw_user_meta_data->>'full_name',
      NEW.raw_user_meta_data->>'name',
      ''
    ),
    NEW.raw_user_meta_data->>'avatar_url',
    'user',
    NOW(),
    NOW()
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Пересоздаём триггер на INSERT
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();


-- 2. Функция синхронизации при ОБНОВЛЕНИИ пользователя
CREATE OR REPLACE FUNCTION public.sync_profile_from_auth()
RETURNS TRIGGER AS $$
DECLARE
  new_full_name TEXT;
  new_avatar_url TEXT;
BEGIN
  -- Извлекаем имя (приоритет: full_name → name)
  new_full_name := COALESCE(
    NEW.raw_user_meta_data->>'full_name',
    NEW.raw_user_meta_data->>'name'
  );
  
  -- Извлекаем аватар
  new_avatar_url := NEW.raw_user_meta_data->>'avatar_url';
  
  -- Обновляем только если что-то изменилось
  UPDATE public.profiles SET
    email = COALESCE(NEW.email, email),
    phone = COALESCE(NEW.phone, phone),
    full_name = COALESCE(new_full_name, full_name),
    avatar_url = COALESCE(new_avatar_url, avatar_url),
    updated_at = NOW()
  WHERE id = NEW.id
    AND (
      email IS DISTINCT FROM NEW.email
      OR phone IS DISTINCT FROM NEW.phone
      OR full_name IS DISTINCT FROM new_full_name
      OR avatar_url IS DISTINCT FROM new_avatar_url
    );
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Создаём триггер на UPDATE
DROP TRIGGER IF EXISTS on_auth_user_updated ON auth.users;
CREATE TRIGGER on_auth_user_updated
  AFTER UPDATE ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_profile_from_auth();


-- 3. Функция для РУЧНОЙ синхронизации всех существующих пользователей
-- Запустите один раз для синхронизации текущих данных
CREATE OR REPLACE FUNCTION public.sync_all_profiles_from_auth()
RETURNS TABLE(synced_count INT, error_count INT) AS $$
DECLARE
  v_synced INT := 0;
  v_errors INT := 0;
  v_user RECORD;
BEGIN
  FOR v_user IN 
    SELECT 
      u.id,
      u.email,
      u.phone,
      COALESCE(u.raw_user_meta_data->>'full_name', u.raw_user_meta_data->>'name') as full_name,
      u.raw_user_meta_data->>'avatar_url' as avatar_url
    FROM auth.users u
  LOOP
    BEGIN
      UPDATE public.profiles SET
        email = COALESCE(v_user.email, email),
        phone = COALESCE(v_user.phone, phone),
        full_name = COALESCE(v_user.full_name, full_name),
        avatar_url = COALESCE(v_user.avatar_url, avatar_url),
        updated_at = NOW()
      WHERE id = v_user.id;
      
      IF FOUND THEN
        v_synced := v_synced + 1;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      v_errors := v_errors + 1;
    END;
  END LOOP;
  
  RETURN QUERY SELECT v_synced, v_errors;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 4. VIEW для удобного чтения данных пользователя
-- Объединяет данные из auth и profiles
CREATE OR REPLACE VIEW public.user_full_profile AS
SELECT 
  p.id,
  -- Из auth (актуальные данные аутентификации)
  u.email as auth_email,
  u.phone as auth_phone,
  u.email_confirmed_at,
  u.phone_confirmed_at,
  u.last_sign_in_at,
  -- Из profiles (могут отставать, но это нормально)
  p.email as profile_email,
  p.phone as profile_phone,
  p.full_name,
  p.avatar_url,
  p.role,
  p.created_at,
  p.updated_at,
  -- Провайдер аутентификации
  u.raw_app_meta_data->>'provider' as auth_provider
FROM public.profiles p
LEFT JOIN auth.users u ON p.id = u.id;

-- RLS для view (наследует от profiles)
-- View автоматически применяет RLS базовых таблиц


-- ============================================
-- ИНСТРУКЦИЯ ПО ПРИМЕНЕНИЮ:
-- ============================================
-- 1. Выполните весь этот скрипт в Supabase SQL Editor
-- 2. Для синхронизации существующих пользователей выполните:
--    SELECT * FROM sync_all_profiles_from_auth();
-- 3. Теперь при любом изменении в auth.users
--    данные автоматически синхронизируются в profiles
-- ============================================


-- Пример: синхронизировать всех существующих пользователей
-- Раскомментируйте и выполните после применения миграции:
-- SELECT * FROM sync_all_profiles_from_auth();
