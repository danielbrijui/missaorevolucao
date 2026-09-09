-- ============================================================================
-- Esquema para a migração futura ao Supabase (Postgres). NÃO executado ainda.
-- Espelha o modelo do app local (index.html / alcadas.js).
-- ============================================================================
create type papel as enum ('presidente','vice','secretario','tesoureiro','diretor_financeiro','coordenador','conselho_fiscal','associado');
create type natureza_despesa as enum ('ordinaria','orcada','projeto','extraordinaria');
create type forma_pagamento as enum ('pix','ted','boleto','dinheiro','cartao_debito','cartao_credito');
create type status_despesa as enum ('aprovacao','assinatura','guia','ratificacao','paga','nao_ratificada','rejeitada','cancelada'); -- estações do fluxo (v2: assinatura só legado)
create type finalidade_conta as enum ('ordinaria','projeto','ressarcimento'); -- 6.1.8

create table config (
  id int primary key default 1 check (id = 1),
  nome text not null default 'Missão Revolução',
  cnpj text,
  tem_diretor_financeiro boolean not null default false,  -- Estatuto 6.5.1
  conta_forn_pai uuid                                     -- conta sintética-mãe dos fornecedores (padrão 2.1)
);
insert into config default values;

-- Um perfil por usuário autenticado (auth.users). Cargo define a alçada.
create table perfis (
  id uuid primary key references auth.users(id) on delete cascade,
  nome text not null,
  email text not null,
  papel papel not null,
  ativo boolean not null default true,
  login text unique,                -- login curto usado na versão local; na nuvem o acesso é pelo e-mail (Supabase Auth)
  pin_hash text,                    -- senha de aprovação (assinatura eletrônica), hash com salt; NUNCA a senha em claro
  pin_salt text,
  criado_em timestamptz default now()
);
-- Na nuvem: senha de ACESSO fica no Supabase Auth (auth.users); a senha de APROVAÇÃO é verificada por função no banco (security definer) que compara o hash e registra a assinatura em aprovacoes/pagamentos com timestamp do servidor.

create table contas_bancarias (
  id uuid primary key default gen_random_uuid(),
  banco text not null, agencia text not null, conta text not null,
  apelido text, finalidade finalidade_conta not null default 'ordinaria',
  pix text, ata text,                        -- 6.1.7: abertura autorizada pela Diretoria e aprovada em Assembleia
  ativa boolean not null default true,
  conta_plano_id uuid                        -- analítica em 1.1.2 (FK adicionada após contas_plano)
);

-- Plano de contas
-- Plano de contas hierárquico: raízes 1 (receita) e 2 (despesa); só contas sem filhos (analíticas) recebem lançamento
create type tipo_conta as enum ('ativo','passivo','pl','receita','despesa');
create table contas_plano (
  id uuid primary key default gen_random_uuid(),
  codigo text not null unique,                 -- 1, 1.1, 1.1.1, 1.1.1.1 ...
  nome text not null,
  pai_id uuid references contas_plano(id),
  tipo tipo_conta,                             -- preenchido só nas raízes; derivado pelo caminho nas demais
  reduzido int unique,                         -- código reduzido sequencial usado nos lançamentos
  classe char(1) not null default 'A' check (classe in ('A','S'))  -- A analítica (recebe partida) / S sintética (só soma)
);

-- Fornecedores: cada um com analítica própria em 2.1 Fornecedores a pagar
create table fornecedores (
  id uuid primary key default gen_random_uuid(),
  tipo_pessoa char(2) not null default 'PJ' check (tipo_pessoa in ('PF','PJ')),
  nome text not null, doc text unique, endereco text, telefone text, email text, pix text,
  ativo boolean not null default true,
  conta_plano_id uuid references contas_plano(id)
);

-- Pagadores (associados, apoiadores, clientes): analítica própria em 1.1.3 Contas a receber
create table pagadores (
  id uuid primary key default gen_random_uuid(),
  categoria text not null default 'associado' check (categoria in ('associado','apoiador','cliente','outro')),
  tipo_pessoa char(2) not null default 'PF' check (tipo_pessoa in ('PF','PJ')),
  nome text not null, doc text unique, endereco text, telefone text, email text, pix text,
  valor_mensal numeric(12,2) not null default 0, dia_venc smallint not null default 10 check (dia_venc between 1 and 28), -- mensalidade (associado) / contribuição (apoiador)
  ativo boolean not null default true, conta_plano_id uuid references contas_plano(id) -- analítica dentro da conta-mãe da categoria (config.conta_rec_pai_*)
);
-- Anexos (comprovante de pagamento, documento fiscal): no Supabase vão para Storage; aqui só a referência
create table anexos (
  id uuid primary key default gen_random_uuid(), despesa_id uuid, receita_id uuid,
  tipo text not null check (tipo in ('comprovante','documento_fiscal')), nome text not null, mime text, storage_path text not null,
  quem uuid references perfis(id), criado_em timestamptz default now()
);

create table projetos (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  orcamento numeric(12,2) not null check (orcamento >= 0),
  data date,                               -- realização (6.1.2.1: orçamento ≥ 90 dias antes; resultados ≤ 60 dias depois)
  coordenador_id uuid references perfis(id), -- associado (6.1.2 a)
  adm_id uuid references perfis(id),         -- ADM Tesoureiro do projeto, associado (6.1.2 b)
  ativo boolean not null default true,
  resultados_ata text, resultados_data date,
  ata text not null,                       -- AGO que aprovou o projeto
  criado_em timestamptz default now()
);

-- Orçamento do projeto (DRE): linhas por conta, aprovado individualmente pelos aprovadores escolhidos
create type status_orcamento as enum ('rascunho','em_aprovacao','aprovado','recusado');
create table orcamentos (
  projeto_id uuid primary key references projetos(id) on delete cascade,
  status status_orcamento not null default 'rascunho',
  ata text, ata_data date, fora_prazo boolean default false,  -- aprovação pela Assembleia (6.1.2.1)
  criado_por uuid references perfis(id), criado_em timestamptz default now(),
  enviado_em timestamptz, aprovado_em timestamptz
);
create table orcamento_linhas (
  id uuid primary key default gen_random_uuid(),
  projeto_id uuid not null references orcamentos(projeto_id) on delete cascade,
  conta_id uuid not null references contas_plano(id),
  descricao text, valor numeric(12,2) not null check (valor > 0)
);
create table orcamento_aprovadores (
  projeto_id uuid not null references orcamentos(projeto_id) on delete cascade,
  usuario_id uuid not null references perfis(id),
  decisao text check (decisao in ('aprovar','rejeitar')), comentario text, data timestamptz,
  primary key (projeto_id, usuario_id)
);

-- Orçamento anual por rubrica (6.1.1), aprovado pela AGO até 30/11
create table orcamento_anual (
  ano char(4) primary key, status status_orcamento not null default 'rascunho',
  ata text, ata_data date, fora_prazo boolean default false, aprovado_por uuid references perfis(id), aprovado_em timestamptz
);
create table orcamento_anual_linhas (
  id uuid primary key default gen_random_uuid(), ano char(4) not null references orcamento_anual(ano) on delete cascade,
  conta_id uuid not null references contas_plano(id), descricao text, valor numeric(12,2) not null check (valor > 0)
);

create table despesas (
  id uuid primary key default gen_random_uuid(),
  num serial,
  descricao text not null,
  fornecedor text not null,
  valor numeric(12,2) not null check (valor > 0),
  competencia date not null,
  vencimento date,
  natureza natureza_despesa not null,
  forma forma_pagamento not null,
  projeto_id uuid references projetos(id),
  conta_id uuid not null references contas_bancarias(id),   -- conta de saída
  conta_plano_id uuid references contas_plano(id),          -- classificação no plano de contas
  dados_favorecido text,
  justificativa text,
  reembolso_diretor boolean not null default false,   -- 6.8.1
  conflito_interesse boolean not null default false,  -- 6.10
  solicitante_id uuid not null references perfis(id),
  rota jsonb not null,                                -- saída de calcularRota(): classe, orcado, naoOrcado, saldoRubrica, etapas (com impedidos/usuarioIds), ratificacao
  sem_autorizacao_previa boolean not null default false, -- 6.1.9
  status status_despesa not null default 'aprovacao',
  aprovada_em timestamptz, guia_em timestamptz,
  criado_em timestamptz default now(),
  constraint projeto_obrigatorio check (natureza <> 'projeto' or projeto_id is not null)
);

create table aprovacoes (
  id bigserial primary key,
  despesa_id uuid not null references despesas(id) on delete cascade,
  etapa int not null,
  usuario_id uuid not null references perfis(id),
  decisao text not null check (decisao in ('aprovar','rejeitar')),
  comentario text,
  ata text,                                 -- quando a etapa é Assembleia
  data timestamptz default now(),
  unique (despesa_id, etapa, usuario_id)    -- cada pessoa vota uma vez por etapa
);

-- Estação 3: cada gestor assina no próprio acesso (6.1.3 / 6.1.4)
create table assinaturas (
  id bigserial primary key,
  despesa_id uuid not null references despesas(id) on delete cascade,
  usuario_id uuid not null references perfis(id),
  papel papel not null,
  comentario text,
  data timestamptz default now(),
  unique (despesa_id, usuario_id)
);

-- Estação 4: registro do pagamento efetuado
create table pagamentos (
  despesa_id uuid primary key references despesas(id) on delete cascade,
  data date not null,
  comprovante text not null,
  registrado_por uuid not null references perfis(id),
  registrado_em timestamptz default now()
);

create table historico (
  id bigserial primary key,
  despesa_id uuid not null references despesas(id) on delete cascade,
  quem uuid references perfis(id),
  o text not null,
  data timestamptz default now()
);

-- Acumulados do mês usados pelo motor (ordinárias 20k, débito 3k, crédito 5k)
create view acumulados_mes as
select date_trunc('month', competencia)::date as mes,
       sum(valor) filter (where natureza = 'ordinaria')     as ordinarias,
       sum(valor) filter (where forma = 'cartao_debito')    as debito,
       sum(valor) filter (where forma = 'cartao_credito')   as credito
from despesas where status not in ('rejeitada','cancelada')
group by 1;

-- ---------------------------------------------------------------- RLS
alter table perfis enable row level security;
alter table despesas enable row level security;
alter table aprovacoes enable row level security;
alter table pagamentos enable row level security;
alter table assinaturas enable row level security;
alter table contas_bancarias enable row level security;
alter table projetos enable row level security;
alter table historico enable row level security;
alter table config enable row level security;

create or replace function meu_papel() returns papel language sql stable security definer as
$$ select papel from perfis where id = auth.uid() and ativo $$;

-- Diretoria e Conselho Fiscal leem tudo (transparência, item 4.1 c)
create policy leitura_diretoria on despesas for select using (meu_papel() is not null);
create policy leitura_aprov on aprovacoes for select using (meu_papel() is not null);
create policy leitura_pag on pagamentos for select using (meu_papel() is not null);
create policy leitura_ass on assinaturas for select using (meu_papel() is not null);
create policy leitura_contas on contas_bancarias for select using (meu_papel() is not null);
create policy leitura_proj on projetos for select using (meu_papel() is not null);
create policy leitura_hist on historico for select using (meu_papel() is not null);
create policy leitura_perfis on perfis for select using (meu_papel() is not null);
create policy leitura_config on config for select using (meu_papel() is not null);

-- Qualquer membro ativo (exceto Conselho Fiscal, que só fiscaliza) lança despesas em seu próprio nome
create policy lancar on despesas for insert with check (solicitante_id = auth.uid() and meu_papel() <> 'conselho_fiscal');
-- Aprovações: o próprio usuário registra o próprio voto (pode ser na despesa que ele lançou —
-- decisão da Diretoria de não aplicar segregação). A validação da etapa/papel fica numa
-- função RPC (aprovar_despesa) que reimplementa podeAprovar() do app.
create policy aprovar on aprovacoes for insert with check (usuario_id = auth.uid());
create policy assinar on assinaturas for insert with check (usuario_id = auth.uid() and meu_papel() in ('tesoureiro','presidente','diretor_financeiro'));
create policy contas_adm on contas_bancarias for all using (meu_papel() in ('tesoureiro','presidente'));
create policy pagar on pagamentos for insert with check (meu_papel() in ('tesoureiro','presidente','diretor_financeiro'));
create policy projetos_adm on projetos for all using (meu_papel() in ('tesoureiro','presidente','secretario'));
create policy config_adm on config for update using (meu_papel() in ('tesoureiro','presidente'));

-- Receitas (recebimentos) e lançamentos contábeis
create type classe_receita as enum ('ordinaria','extraordinaria','projeto_orcada','projeto_nao_orcada'); -- 6.1.3 espelhado para receitas
create table receitas (
  id uuid primary key default gen_random_uuid(),
  descricao text not null, categoria text not null default 'diversos' check (categoria in ('associado','apoiador','cliente','outro','diversos')),
  pagador_id uuid references pagadores(id), origem text, classe classe_receita not null default 'ordinaria',
  valor numeric(12,2) not null check (valor > 0), status text not null default 'recebida' check (status in ('aberta','recebida')),
  vencimento date, competencia char(7), -- competencia 'AAAA-MM' preenchida nas mensalidades geradas em lote (única por pagador/mês)
  data date, valor_recebido numeric(12,2), diferenca numeric(12,2),
  conta_plano_id uuid not null references contas_plano(id), conta_id uuid references contas_bancarias(id),
  forma text, projeto_id uuid references projetos(id), comprovante text,
  lanc_provisao uuid, lancamento_id uuid, recebido_por uuid references perfis(id), recebido_em timestamptz,
  recebimentos_estornados jsonb not null default '[]', -- estornos de recebimento (o título volta a 'aberta')
  quem uuid references perfis(id), criado_em timestamptz default now(), estornada text,
  unique (pagador_id, competencia)
);
-- Inscritos em TOP/eventos (inscrição gerida no site do Legendários Global; o repasse líquido entra na conta da Associação)
-- projetos.conta_inscricoes / conta_royalties: contas contábeis padrão do projeto (ex.: raiz 6/7)
create table inscritos (
  id uuid primary key default gen_random_uuid(), projeto_id uuid not null references projetos(id),
  nome text not null, numero text, tipo text not null default 'novato' check (tipo in ('novato','servidor','coordenador')),
  bruto numeric(12,2) not null check (bruto > 0), deducao numeric(12,2) not null default 0, liquido numeric(12,2) not null,
  contato text, obs text, data_repasse date, conta_id uuid references contas_bancarias(id), ref text,
  lancamento_id uuid, repassado_por uuid references perfis(id), repassado_em timestamptz, estornos jsonb not null default '[]',
  quem uuid references perfis(id), criado_em timestamptz default now(), unique (projeto_id, numero)
);
create type origem_lanc as enum ('despesa','receita','estorno','manual','encerramento');
create table lancamentos (
  id uuid primary key default gen_random_uuid(), num serial, data date not null, historico text not null,
  origem origem_lanc not null default 'manual', origem_id uuid, estornado_por uuid references lancamentos(id),
  natureza text check (natureza in ('receita','despesa','patrimonial')), classe classe_receita, -- natureza/classe (6.1.3) do lançamento; projeto via lancamentos_projetos
  quem uuid references perfis(id), criado_em timestamptz default now()
);
create table partidas (
  id bigserial primary key, lancamento_id uuid not null references lancamentos(id) on delete cascade,
  conta_id uuid not null references contas_plano(id), debito numeric(12,2) not null default 0, credito numeric(12,2) not null default 0
);
-- Regra: soma(debito) = soma(credito) por lançamento — validar em trigger/RPC. Lançamentos nunca são apagados: estorna-se.
alter table contas_bancarias add constraint fk_conta_plano foreign key (conta_plano_id) references contas_plano(id);

-- Exercícios encerrados: trava lançamentos com data <= ate (validar em trigger)
create table exercicios (
  ano char(4) primary key, de date not null, ate date not null,
  lancamento_id uuid references lancamentos(id), receitas numeric(12,2), despesas numeric(12,2), resultado numeric(12,2),
  ata text, quem uuid references perfis(id), encerrado_em timestamptz default now()
);
-- Atas das reuniões (Assembleia, Diretoria, Conselho Fiscal)
create type tipo_ata as enum ('ago','age','diretoria','fiscal','fundacao','outra');
create type status_ata as enum ('rascunho','aprovada','registrada');
create table atas (
  id uuid primary key default gen_random_uuid(),
  tipo tipo_ata not null, numero text not null unique, status status_ata not null default 'rascunho',
  data date not null, hora text, local text, presidiu text, secretariou text, quorum text,
  presentes uuid[] default '{}', convidados text, pauta text not null, deliberacoes text not null,
  registro_cartorio text, registro_numero text, registro_data date, obs text,
  quem uuid references perfis(id), criado_em timestamptz default now(), editado_em timestamptz
);

-- Próximo passo na migração: portar calcularRota() para plpgsql (ou Edge Function em JS
-- reutilizando alcadas.js sem alteração) e criar as RPCs lancar_despesa / aprovar_despesa /
-- registrar_pagamento, que centralizam as transições de status.
