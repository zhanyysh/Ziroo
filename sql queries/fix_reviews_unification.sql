-- Объединяем рейтинги и отзывы в одну таблицу branch_reviews
-- 1. Добавляем уникальность, чтобы один юзер мог оставить только 1 отзыв филиалу
CREATE UNIQUE INDEX IF NOT EXISTS idx_branch_reviews_user_branch 
ON branch_reviews (user_id, branch_id);

-- 2. Обновляем политики (RLS), чтобы можно было менять свои отзывы
DROP POLICY IF EXISTS "Users can update their own reviews" ON branch_reviews;
CREATE POLICY "Users can update their own reviews" 
ON branch_reviews FOR UPDATE 
TO authenticated 
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- 3. Разрешаем UPSERT (Вставку или Обновление)
DROP POLICY IF EXISTS "Users can insert their own reviews" ON branch_reviews;
CREATE POLICY "Users can insert their own reviews" 
ON branch_reviews FOR INSERT 
TO authenticated 
WITH CHECK (auth.uid() = user_id);
