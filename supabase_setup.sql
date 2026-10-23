-- =====================================================================
--  HOLISTIC ACADEMY — SCHOOL MANAGEMENT SYSTEM
--  Database setup for Supabase (PostgreSQL)
--
--  How to use: Supabase dashboard → SQL Editor → New query →
--  paste this whole file → Run. It is safe to run again later.
--
--  What it gives you:
--   * One shared database that many staff can use at the same time.
--   * Roles enforced by the database itself (Row Level Security), so a
--     teacher's login can never read fees, expenses or payroll, even
--     if someone tampers with the web page.
--   * Duplicate protection: every record has a fixed ID, and natural
--     keys (one attendance mark per child per day, one score per child
--     per subject per term, one feeding entry per class per day, one
--     enrolment per child name + date of birth) are UNIQUE.
--   * An automatic activity log so the proprietor can see who did what.
--   * The FIRST account that signs up becomes the Proprietor. Everyone
--     after that waits as "pending" until the Proprietor/Admin approves.
-- =====================================================================

set client_min_messages = warning;
create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- Staff profiles (one per login)
-- ---------------------------------------------------------------------
create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  email       text,
  full_name   text not null default '',
  role        text not null default 'pending'
              check (role in ('pending','proprietor','admin','headmistress','treasurer','teacher')),
  class_name  text,                       -- teachers: limit to one class (blank = all classes)
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);

create or replace function public.app_role() returns text
language sql stable security definer set search_path = public as $$
  select role from public.profiles where id = auth.uid() and active
$$;

create or replace function public.app_class() returns text
language sql stable security definer set search_path = public as $$
  select nullif(class_name, '') from public.profiles where id = auth.uid() and active
$$;

create or replace function public.has_role(variadic roles text[]) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.app_role() = any(roles), false)
$$;

create or replace function public.app_user_name() returns text
language sql stable security definer set search_path = public as $$
  select coalesce(nullif(full_name, ''), email) from public.profiles where id = auth.uid()
$$;

-- New sign-up → profile. First ever account becomes the Proprietor.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, full_name, role)
  values (
    new.id, new.email,
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    case when exists (select 1 from public.profiles where role = 'proprietor') then 'pending' else 'proprietor' end
  )
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- Only the Proprietor can create, change or remove a Proprietor, and
-- nobody can change their own role or switch themselves off.
create or replace function public.guard_profile_update() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.id = auth.uid() and (new.role is distinct from old.role or new.active is distinct from old.active) then
    raise exception 'You cannot change your own role or status.';
  end if;
  if (old.role = 'proprietor' or new.role = 'proprietor') and public.app_role() <> 'proprietor' then
    raise exception 'Only the Proprietor can assign or change the Proprietor role.';
  end if;
  return new;
end $$;

drop trigger if exists guard_profile_update on public.profiles;
create trigger guard_profile_update before update on public.profiles
  for each row execute function public.guard_profile_update();

-- ---------------------------------------------------------------------
-- School settings (classes, subjects, fee amounts, term …)
-- finance = true rows are hidden from teachers.
-- ---------------------------------------------------------------------
create table if not exists public.settings (
  key         text primary key,
  value       jsonb not null,
  finance     boolean not null default false,
  updated_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Students (enrolment)
-- ---------------------------------------------------------------------
create sequence if not exists public.student_no_seq;

create table if not exists public.students (
  id              uuid primary key default gen_random_uuid(),
  student_no      text unique,
  full_name       text not null check (btrim(full_name) <> ''),
  class_name      text not null,
  gender          text,
  dob             date,
  father_name     text,
  mother_name     text,
  guardian_name   text,
  guardian_phone  text,
  health_note     text,
  admission_date  date default current_date,
  status          text not null default 'Active' check (status in ('Active','Left','Graduated')),
  recorded_by     text,
  created_by      uuid default auth.uid(),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint students_parent_required check (
    coalesce(btrim(father_name), '') <> '' or coalesce(btrim(mother_name), '') <> '' or coalesce(btrim(guardian_name), '') <> ''
  )
);
-- The same child (name + date of birth) can only be enrolled once.
create unique index if not exists students_unique_child
  on public.students (lower(btrim(full_name)), dob) where dob is not null;

create or replace function public.set_student_no() returns trigger
language plpgsql as $$
begin
  if new.student_no is null or new.student_no = '' then
    new.student_no := 'HA-' || to_char(coalesce(new.admission_date, current_date), 'YYYY') || '-' ||
                      lpad(nextval('public.student_no_seq')::text, 4, '0');
  end if;
  return new;
end $$;
drop trigger if exists set_student_no on public.students;
create trigger set_student_no before insert on public.students
  for each row execute function public.set_student_no();

-- ---------------------------------------------------------------------
-- Academic records
-- ---------------------------------------------------------------------
create table if not exists public.attendance (
  id           uuid primary key default gen_random_uuid(),
  student_id   uuid not null references public.students(id) on delete cascade,
  class_name   text not null,
  date         date not null,
  status       text not null check (status in ('Present','Absent','Late')),
  recorded_by  text,
  created_by   uuid default auth.uid(),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (student_id, date)
);

create table if not exists public.grades (
  id             uuid primary key default gen_random_uuid(),
  student_id     uuid not null references public.students(id) on delete cascade,
  class_name     text not null,
  subject        text not null,
  term           text not null,
  academic_year  text not null,
  score          numeric(5,2) not null check (score between 0 and 100),
  grade          text,
  remarks        text,
  recorded_by    text,
  created_by     uuid default auth.uid(),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique (student_id, subject, term, academic_year)
);

create table if not exists public.incidents (
  id            uuid primary key default gen_random_uuid(),
  date          date not null,
  student_id    uuid references public.students(id) on delete cascade,
  class_name    text not null,
  type          text not null,
  description   text not null,
  action_taken  text,
  recorded_by   text,
  created_by    uuid default auth.uid(),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Finance (hidden from teachers)
-- ---------------------------------------------------------------------
create table if not exists public.fee_payments (
  id           uuid primary key default gen_random_uuid(),
  student_id   uuid references public.students(id) on delete set null,
  student_name text not null,
  class_name   text not null,
  fee_type     text not null default 'School Fees',
  period       text not null,                -- e.g. 2026-10 (monthly) or 2026/2027 Term 1 (termly)
  amount       numeric(12,2) not null check (amount > 0),
  method       text not null default 'Cash',
  date_paid    date not null default current_date,
  note         text,
  recorded_by  text,
  created_by   uuid default auth.uid(),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create table if not exists public.feeding_records (
  id              uuid primary key default gen_random_uuid(),
  date            date not null,
  class_name      text not null,
  students_count  integer not null check (students_count >= 0),
  rate            numeric(10,2) not null,
  amount          numeric(12,2) not null,
  recorded_by     text,
  created_by      uuid default auth.uid(),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (date, class_name)
);

create table if not exists public.expenses (
  id           uuid primary key default gen_random_uuid(),
  date         date not null,
  category     text not null,                -- 'Feeding' = feeding programme expense
  description  text not null,
  amount       numeric(12,2) not null check (amount > 0),
  paid_by      text,
  recorded_by  text,
  created_by   uuid default auth.uid(),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create table if not exists public.payroll (
  id            uuid primary key default gen_random_uuid(),
  staff_name    text not null,
  staff_role    text,
  month         text not null,               -- 2026-10
  basic         numeric(12,2) not null default 0,
  allowance     numeric(12,2) not null default 0,
  deductions    numeric(12,2) not null default 0,
  net           numeric(12,2) not null default 0,
  payment_date  date,
  status        text not null default 'Paid',
  recorded_by   text,
  created_by    uuid default auth.uid(),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (staff_name, month)
);

-- ---------------------------------------------------------------------
-- Activity log (written only by the database)
-- ---------------------------------------------------------------------
create table if not exists public.activity_log (
  id          bigserial primary key,
  at          timestamptz not null default now(),
  user_id     uuid,
  user_name   text,
  action      text not null,
  table_name  text not null,
  record_id   uuid,
  summary     text
);
create index if not exists activity_log_at on public.activity_log (at desc);

-- Fills recorded_by / updated_at on every save.
create or replace function public.stamp_row() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.updated_at := now();
  if tg_op = 'INSERT' then
    new.created_by := coalesce(auth.uid(), new.created_by);
  end if;
  new.recorded_by := coalesce(public.app_user_name(), new.recorded_by);
  return new;
end $$;

create or replace function public.log_change() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  r jsonb := to_jsonb(coalesce(new, old));
  s text;
begin
  s := case tg_table_name
    when 'students'        then r->>'full_name' || ' (' || (r->>'class_name') || ')'
    when 'attendance'      then (r->>'class_name') || ' ' || (r->>'date') || ': ' || (r->>'status')
    when 'grades'          then (r->>'class_name') || ' ' || (r->>'subject') || ' ' || (r->>'term') || ': ' || (r->>'score')
    when 'incidents'       then (r->>'class_name') || ' ' || (r->>'type')
    when 'fee_payments'    then (r->>'student_name') || ' ' || (r->>'fee_type') || ' GHS ' || (r->>'amount')
    when 'feeding_records' then (r->>'class_name') || ' ' || (r->>'date') || ': ' || (r->>'students_count') || ' children'
    when 'expenses'        then (r->>'category') || ': ' || (r->>'description') || ' GHS ' || (r->>'amount')
    when 'payroll'         then (r->>'staff_name') || ' ' || (r->>'month')
    else null end;
  insert into public.activity_log (user_id, user_name, action, table_name, record_id, summary)
  values (auth.uid(), public.app_user_name(), lower(tg_op), tg_table_name, (r->>'id')::uuid, s);
  return null;
end $$;

do $$
declare t text;
begin
  foreach t in array array['students','attendance','grades','incidents','fee_payments','feeding_records','expenses','payroll'] loop
    execute format('drop trigger if exists stamp_row on public.%I', t);
    execute format('create trigger stamp_row before insert or update on public.%I for each row execute function public.stamp_row()', t);
    execute format('drop trigger if exists log_change on public.%I', t);
    execute format('create trigger log_change after insert or update or delete on public.%I for each row execute function public.log_change()', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- Row Level Security: who can see and change what
-- ---------------------------------------------------------------------
alter table public.profiles        enable row level security;
alter table public.settings        enable row level security;
alter table public.students        enable row level security;
alter table public.attendance      enable row level security;
alter table public.grades          enable row level security;
alter table public.incidents       enable row level security;
alter table public.fee_payments    enable row level security;
alter table public.feeding_records enable row level security;
alter table public.expenses        enable row level security;
alter table public.payroll         enable row level security;
alter table public.activity_log    enable row level security;

do $$
declare p record;
begin
  -- drop old policies so re-running this file stays clean
  for p in select policyname, tablename from pg_policies where schemaname = 'public' loop
    execute format('drop policy %I on public.%I', p.policyname, p.tablename);
  end loop;
end $$;

-- profiles
create policy profiles_read on public.profiles for select
  using (id = auth.uid() or public.has_role('proprietor','admin'));
create policy profiles_update on public.profiles for update
  using (public.has_role('proprietor','admin')) with check (public.has_role('proprietor','admin'));
create policy profiles_delete on public.profiles for delete
  using (public.has_role('proprietor') and id <> auth.uid());

-- settings
create policy settings_read on public.settings for select
  using (public.has_role('proprietor','admin','headmistress','treasurer','teacher')
         and (not finance or public.has_role('proprietor','admin','headmistress','treasurer')));
create policy settings_write on public.settings for all
  using (public.has_role('proprietor','admin')) with check (public.has_role('proprietor','admin'));

-- students: everyone approved can read (teachers: own class only); office enrols
create policy students_read on public.students for select
  using (public.has_role('proprietor','admin','headmistress','treasurer')
         or (public.has_role('teacher') and (public.app_class() is null or class_name = public.app_class())));
create policy students_insert on public.students for insert
  with check (public.has_role('proprietor','admin','headmistress'));
create policy students_update on public.students for update
  using (public.has_role('proprietor','admin','headmistress')) with check (public.has_role('proprietor','admin','headmistress'));
create policy students_delete on public.students for delete
  using (public.has_role('proprietor','admin'));

-- attendance, grades, incidents: teaching staff (teachers limited to their class)
do $$
declare t text;
begin
  foreach t in array array['attendance','grades','incidents'] loop
    execute format($f$
      create policy %1$s_read on public.%1$I for select using (
        public.has_role('proprietor','admin','headmistress')
        or (public.has_role('teacher') and (public.app_class() is null or class_name = public.app_class())));
      create policy %1$s_insert on public.%1$I for insert with check (
        public.has_role('proprietor','admin','headmistress')
        or (public.has_role('teacher') and (public.app_class() is null or class_name = public.app_class())));
      create policy %1$s_update on public.%1$I for update using (
        public.has_role('proprietor','admin','headmistress')
        or (public.has_role('teacher') and (public.app_class() is null or class_name = public.app_class())))
        with check (
        public.has_role('proprietor','admin','headmistress')
        or (public.has_role('teacher') and (public.app_class() is null or class_name = public.app_class())));
      create policy %1$s_delete on public.%1$I for delete using (public.has_role('proprietor','admin','headmistress'));
    $f$, t);
  end loop;
end $$;

-- money: proprietor, admin, headmistress, treasurer
do $$
declare t text;
begin
  foreach t in array array['fee_payments','feeding_records','expenses'] loop
    execute format($f$
      create policy %1$s_read on public.%1$I for select using (public.has_role('proprietor','admin','headmistress','treasurer'));
      create policy %1$s_insert on public.%1$I for insert with check (public.has_role('proprietor','admin','headmistress','treasurer'));
      create policy %1$s_update on public.%1$I for update using (public.has_role('proprietor','admin','headmistress','treasurer'))
        with check (public.has_role('proprietor','admin','headmistress','treasurer'));
      create policy %1$s_delete on public.%1$I for delete using (public.has_role('proprietor','admin','headmistress'));
    $f$, t);
  end loop;
end $$;

-- payroll: proprietor and admin only
create policy payroll_all on public.payroll for all
  using (public.has_role('proprietor','admin')) with check (public.has_role('proprietor','admin'));

-- activity log: proprietor and admin can read; nobody writes directly
create policy activity_read on public.activity_log for select
  using (public.has_role('proprietor','admin'));

grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage, select on all sequences in schema public to authenticated;
revoke all on public.activity_log from authenticated;
grant select on public.activity_log to authenticated;

-- ---------------------------------------------------------------------
-- Live updates: other staff see new records without refreshing
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach t in array array['students','attendance','grades','incidents','fee_payments','feeding_records','expenses','payroll','settings'] loop
      if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
        execute format('alter publication supabase_realtime add table public.%I', t);
      end if;
    end loop;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Helpful indexes for speed as the school grows
-- ---------------------------------------------------------------------
create index if not exists attendance_date   on public.attendance (date);
create index if not exists attendance_class  on public.attendance (class_name, date);
create index if not exists grades_class_term on public.grades (class_name, term, academic_year);
create index if not exists fees_period       on public.fee_payments (period);
create index if not exists fees_student      on public.fee_payments (student_id);
create index if not exists fees_date         on public.fee_payments (date_paid);
create index if not exists feeding_date      on public.feeding_records (date);
create index if not exists expenses_date     on public.expenses (date);
create index if not exists students_class    on public.students (class_name);
