-- Barbearia Alex: rode este arquivo inteiro no Supabase (SQL Editor > New query > Run)
create table public.servicos (nome text primary key, preco numeric(8,2) not null);
insert into public.servicos values ('Corte',35),('Barba',25),('Corte + Barba',55),('Sobrancelha',10);

create table public.barbeiros (user_id uuid primary key references auth.users(id) on delete cascade);

create table public.agendamentos (
  id uuid primary key default gen_random_uuid(),
  barbeiro text not null default 'alex',
  nome text not null check (char_length(nome) between 2 and 80),
  telefone text not null check (char_length(telefone) between 10 and 20),
  servico text not null references public.servicos(nome),
  preco numeric(8,2) not null,
  data date not null,
  hora text not null,
  status text not null default 'pendente' check (status in ('pendente','confirmado','concluido','cancelado')),
  criado_em timestamptz not null default now()
);
-- Impede dois clientes no mesmo horário, mesmo barbeiro (cancelado libera o horário)
create unique index agendamento_unico on public.agendamentos (barbeiro, data, hora) where status <> 'cancelado';

alter table public.servicos enable row level security;
alter table public.barbeiros enable row level security;
alter table public.agendamentos enable row level security;

create function public.is_barbeiro() returns boolean language sql security definer set search_path=public stable
as $$ select exists (select 1 from public.barbeiros where user_id = auth.uid()) $$;

create policy "servicos publicos" on public.servicos for select using (true);
create policy "barbeiro le" on public.agendamentos for select to authenticated using (public.is_barbeiro());
create policy "barbeiro atualiza" on public.agendamentos for update to authenticated using (public.is_barbeiro()) with check (public.is_barbeiro());
-- Sem política de insert/delete: o cliente só cria agendamento pela função abaixo.

create function public.horarios_ocupados(p_data date) returns table(hora text)
language sql security definer set search_path=public stable
as $$ select a.hora from public.agendamentos a where a.data = p_data and a.barbeiro='alex' and a.status <> 'cancelado' $$;

create function public.agendar(p_nome text, p_telefone text, p_servico text, p_data date, p_hora text) returns void
language plpgsql security definer set search_path=public as $$
declare v_preco numeric;
begin
  select preco into v_preco from public.servicos where nome = p_servico;
  if v_preco is null then raise exception 'servico_invalido'; end if;
  if char_length(trim(p_nome)) < 2 or char_length(regexp_replace(p_telefone,'\D','','g')) < 10 then raise exception 'dados_invalidos'; end if;
  if p_hora <> all (array['09:00','09:30','10:00','10:30','11:00','11:30','13:00','13:30','14:00','14:30','15:00','15:30','16:00','16:30','17:00','17:30']) then raise exception 'horario_invalido'; end if;
  if p_data < (now() at time zone 'America/Bahia')::date or extract(dow from p_data) = 0 then raise exception 'data_invalida'; end if;
  insert into public.agendamentos (nome, telefone, servico, preco, data, hora) values (trim(p_nome), trim(p_telefone), p_servico, v_preco, p_data, p_hora);
exception when unique_violation then raise exception 'horario_ocupado';
end $$;

grant execute on function public.horarios_ocupados(date), public.agendar(text,text,text,date,text) to anon, authenticated;

alter publication supabase_realtime add table public.agendamentos;

-- DEPOIS de criar o usuário do Alex (veja o LEIA-ME), rode (troque o e-mail):
-- insert into public.barbeiros (user_id) select id from auth.users where email = 'EMAIL_DO_ALEX@exemplo.com';
