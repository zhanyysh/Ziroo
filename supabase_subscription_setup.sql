-- Добавляем поля для статуса подписки в таблицу профилей
ALTER TABLE profiles 
ADD COLUMN IF NOT EXISTS is_premium BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS subscription_status TEXT DEFAULT 'free', -- 'active', 'expired', 'free'
ADD COLUMN IF NOT EXISTS subscription_end_date TIMESTAMPTZ;

-- Обновляем политику RLS, чтобы пользователи могли читать свой статус подписки (если еще не настроено)
-- (Обычно чтение своего профиля уже разрешено, но убедимся)
-- Предполагается, что обновление (UPDATE) этих полей должно быть разрешено ТОЛЬКО сервис-роли (через вебхуки) или админу, 
-- но пока оставим как есть, так как RevenueCat обычно используется на клиенте для проверки прав доступа, 
-- а синхронизация с базой - это отдельная настройка вебхуков.

-- Для удобства, создадим функцию, чтобы проверять премиум статус
CREATE OR REPLACE FUNCTION is_premium_user()
RETURNS BOOLEAN AS $$
BEGIN
  RETURN (SELECT is_premium FROM profiles WHERE id = auth.uid());
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
