-- Create user_favorites table
create table public.user_favorites (
  id uuid not null default gen_random_uuid (),
  user_id uuid not null references auth.users (id) on delete cascade,
  company_id uuid not null references public.companies (id) on delete cascade,
  created_at timestamp with time zone not null default now(),
  constraint user_favorites_pkey primary key (id),
  constraint user_favorites_user_company_unique unique (user_id, company_id)
);

-- Enable RLS
alter table public.user_favorites enable row level security;

-- Policies
create policy "Users can view their own favorites" on public.user_favorites
  for select using (auth.uid() = user_id);

create policy "Users can insert their own favorites" on public.user_favorites
  for insert with check (auth.uid() = user_id);

create policy "Users can delete their own favorites" on public.user_favorites
  for delete using (auth.uid() = user_id);
