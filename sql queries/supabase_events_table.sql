-- Create table for Company Events / Promotions
create table public.company_events (
  id uuid not null default gen_random_uuid (),
  company_id uuid not null references public.companies (id) on delete cascade,
  title text not null,
  description text,
  image_url text,
  created_at timestamp with time zone not null default now(),
  constraint company_events_pkey primary key (id)
);

-- Enable RLS
alter table public.company_events enable row level security;

-- Policies
create policy "Public can view events" on public.company_events
  for select using (true);

create policy "Admins can insert events" on public.company_events
  for insert with check (
    exists (
      select 1 from public.profiles
      where profiles.id = auth.uid() and profiles.role = 'admin'
    )
  );

create policy "Admins can update events" on public.company_events
  for update using (
    exists (
      select 1 from public.profiles
      where profiles.id = auth.uid() and profiles.role = 'admin'
    )
  );

create policy "Admins can delete events" on public.company_events
  for delete using (
    exists (
      select 1 from public.profiles
      where profiles.id = auth.uid() and profiles.role = 'admin'
    )
  );

-- Storage bucket for event images (if not exists)
insert into storage.buckets (id, name, public)
values ('event_images', 'event_images', true)
on conflict (id) do nothing;

create policy "Public can view event images" on storage.objects
  for select using ( bucket_id = 'event_images' );

create policy "Admins can upload event images" on storage.objects
  for insert with check (
    bucket_id = 'event_images' and
    exists (
      select 1 from public.profiles
      where profiles.id = auth.uid() and profiles.role = 'admin'
    )
  );
