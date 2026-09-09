-- ============================================================
-- Missão Revolução — Tesouraria online · script de criação (rodar UMA vez no Supabase → SQL Editor)
-- Cria: estado compartilhado (JSON versionado), sinal de atualização (realtime), senha de aprovação por usuário
-- (hash no servidor), bucket de anexos e as políticas de acesso. Pode ser reexecutado sem estragar nada.
-- ============================================================
create extension if not exists pgcrypto with schema extensions;

-- 1) Estado do sistema: um único documento JSON, com versão para evitar que duas pessoas se sobrescrevam
create table if not exists public.estado (
  id int primary key,
  dados jsonb,
  versao int not null default 0,
  atualizado_em timestamptz default now(),
  atualizado_por uuid
);
insert into public.estado (id, dados, versao) values (1, null, 0) on conflict (id) do nothing;

-- 2) Sinal leve para o realtime (evita mandar o JSON inteiro pelo canal)
create table if not exists public.sinal (id int primary key, versao int, em timestamptz);
insert into public.sinal (id, versao, em) values (1, 0, now()) on conflict (id) do nothing;
create or replace function public.tg_sinal() returns trigger language plpgsql security definer set search_path = public as $$
begin update public.sinal set versao = new.versao, em = now() where id = 1; return new; end $$;
drop trigger if exists estado_sinal on public.estado;
create trigger estado_sinal after update on public.estado for each row execute function public.tg_sinal();

-- 3) Senha de aprovação (assinatura eletrônica): só o hash com salt, verificado no servidor
create table if not exists public.pins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  hash text not null, salt text not null,
  criado_em timestamptz default now(), alterado_em timestamptz
);

-- 4) Segurança: só usuários logados leem/gravam; ninguém lê o hash de outro
alter table public.estado enable row level security;
alter table public.sinal  enable row level security;
alter table public.pins   enable row level security;
drop policy if exists "estado ler" on public.estado;     create policy "estado ler"    on public.estado for select to authenticated using (true);
drop policy if exists "estado gravar" on public.estado;  create policy "estado gravar" on public.estado for update to authenticated using (true) with check (true);
drop policy if exists "estado criar" on public.estado;   create policy "estado criar"  on public.estado for insert to authenticated with check (true);
drop policy if exists "sinal ler" on public.sinal;       create policy "sinal ler"     on public.sinal  for select to authenticated using (true);
drop policy if exists "pin proprio" on public.pins;      create policy "pin proprio"   on public.pins   for select to authenticated using (user_id = auth.uid());

-- 5) Funções da senha de aprovação
create or replace function public.tem_pin() returns boolean language sql security definer set search_path = public stable as $$
  select exists (select 1 from public.pins where user_id = auth.uid()) $$;

create or replace function public.definir_pin(p_atual text, p_novo text) returns boolean language plpgsql security definer set search_path = public as $$
declare r public.pins%rowtype; s text;
begin
  if auth.uid() is null or length(coalesce(p_novo, '')) < 4 then return false; end if;
  select * into r from public.pins where user_id = auth.uid();
  if found and r.hash <> encode(extensions.digest(r.salt || '|' || coalesce(p_atual, ''), 'sha256'), 'hex') then return false; end if;
  s := encode(extensions.gen_random_bytes(12), 'hex');
  insert into public.pins (user_id, hash, salt, alterado_em) values (auth.uid(), encode(extensions.digest(s || '|' || p_novo, 'sha256'), 'hex'), s, now())
  on conflict (user_id) do update set hash = excluded.hash, salt = excluded.salt, alterado_em = now();
  return true;
end $$;

create or replace function public.verificar_pin(p text) returns boolean language sql security definer set search_path = public stable as $$
  select exists (select 1 from public.pins where user_id = auth.uid() and hash = encode(extensions.digest(salt || '|' || p, 'sha256'), 'hex')) $$;

-- Tesoureiro/Presidente (conforme o cadastro de usuários do sistema) podem apagar a senha de aprovação de alguém que esqueceu
create or replace function public.apagar_pin(alvo uuid) returns boolean language plpgsql security definer set search_path = public as $$
begin
  if not exists (
    select 1 from public.estado e, jsonb_array_elements(e.dados->'usuarios') u
    where e.id = 1 and u->>'authId' = auth.uid()::text and u->>'papel' in ('tesoureiro', 'presidente') and coalesce((u->>'ativo')::boolean, true)
  ) then return false; end if;
  delete from public.pins where user_id = alvo; return true;
end $$;

revoke all on function public.tem_pin(), public.definir_pin(text, text), public.verificar_pin(text), public.apagar_pin(uuid) from public;
grant execute on function public.tem_pin(), public.definir_pin(text, text), public.verificar_pin(text), public.apagar_pin(uuid) to authenticated;

-- 6) Realtime no sinal
do $$ begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'sinal') then
    alter publication supabase_realtime add table public.sinal;
  end if;
end $$;

-- 7) Anexos (comprovantes, notas): bucket privado, só logados
insert into storage.buckets (id, name, public) values ('anexos', 'anexos', false) on conflict (id) do nothing;
drop policy if exists "anexos ler" on storage.objects;    create policy "anexos ler"    on storage.objects for select to authenticated using (bucket_id = 'anexos');
drop policy if exists "anexos gravar" on storage.objects; create policy "anexos gravar" on storage.objects for insert to authenticated with check (bucket_id = 'anexos');
