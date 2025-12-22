-- Таблица оценок
CREATE TABLE IF NOT EXISTS branch_ratings (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  created_at TIMESTAMPTZ DEFAULT now(),
  user_id UUID REFERENCES auth.users(id) NOT NULL,
  branch_id UUID REFERENCES company_branches(id) ON DELETE CASCADE NOT NULL,
  rating INTEGER CHECK (rating >= 1 AND rating <= 5),
  comment TEXT,
  -- Уникальное ограничение: один пользователь может оценить филиал только один раз
  UNIQUE(user_id, branch_id)
);

-- Включаем RLS
ALTER TABLE branch_ratings ENABLE ROW LEVEL SECURITY;

-- Политика: Все могут читать оценки
CREATE POLICY "Anyone can read ratings" 
ON branch_ratings FOR SELECT 
TO authenticated 
USING (true);

-- Политика: Пользователь может добавлять/менять ТОЛЬКО свои оценки
CREATE POLICY "Users can insert their own ratings" 
ON branch_ratings FOR INSERT 
TO authenticated 
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own ratings" 
ON branch_ratings FOR UPDATE 
TO authenticated 
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);
