-- Добавляем колонку приоритета, если её нет
ALTER TABLE company_branches ADD COLUMN IF NOT EXISTS map_priority int DEFAULT 0;

-- 0 = Мелкий (точка)
-- 1 = Средний (магазин)
-- 2 = Крупный (VIP / логотип)
