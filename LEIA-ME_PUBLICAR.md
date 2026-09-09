# Publicar a Tesouraria — passo a passo (projeto novo)

Suba **esta pasta inteira** (todos os arquivos, sem subpasta) para o GitHub/Netlify. O arquivo inicial é `index.html`.

## 1. Supabase (banco) — 5 minutos
1. Abra o projeto novo → **SQL Editor** → cole todo o conteúdo de `supabase_setup.sql` → **Run**. Pode rodar de novo sem estragar nada.
2. **Project Settings → API Keys**: copie a **Project URL** (https://xxxx.supabase.co) e a chave **publishable** (`sb_publishable_...`) ou a *anon public*.
3. Abra `config.js` e cole os dois valores no lugar dos textos `COLE_AQUI_...`. Salve.
4. **Authentication → Sign In / Providers → Email**: deixe habilitado. "Confirm email" ligado obriga confirmar o e-mail no primeiro acesso (recomendado).
5. **Authentication → URL Configuration**: em *Site URL* coloque o endereço do site no Netlify (ex.: https://seu-site.netlify.app) e adicione o mesmo em *Redirect URLs*. Faça isso depois do passo 2 do Netlify, quando souber o endereço.

## 2. GitHub + Netlify
1. Coloque os arquivos desta pasta no repositório (na raiz, ou informe a subpasta em *Base directory* / *Publish directory* no Netlify). Não há build: *Build command* vazio, *Publish directory* = a pasta onde está o `index.html`.
2. Netlify → **Site configuration → Access & security**: confira que **não** há proteção por senha nem "Visitor access" ativa — senão a linha do tempo abre com erro 401 e o celular não entra.
3. `netlify.toml` já vai junto (libera a linha do tempo dentro do site e cabeçalhos de segurança).

## 3. Primeiro acesso
1. No site, clique em **Primeiro acesso** com o e-mail que está no seu cadastro de usuário (Tesoureiro). Confirme o e-mail se pedido e entre.
2. Na primeira entrada o sistema cria a senha de aprovação e envia para a nuvem os dados que estavam no navegador do computador (se houver). Dali em diante o banco é a fonte da verdade.
3. Se o sistema abrir com dados de fábrica: **Cadastros → Configurações → Dados → Restaurar backup** com o JSON baixado do sistema antigo ("Baixar backup (JSON)", no mesmo lugar — faça isso antes de desligar o antigo).
4. Demais usuários: cadastre nome, cargo e **e-mail** em Cadastros → Usuários; cada um faz "Primeiro acesso" com esse e-mail.
5. Gestão do TOP → Linha do tempo: se aparecer o modelo de fábrica, clique em **Carregar TOP FEV 2027**.

## Checagem rápida
- `config.js` sem os textos `COLE_AQUI` → senão o site roda em modo local (só no navegador de cada um).
- Abrir no celular: menu ☰, barra inferior. Chrome → "Adicionar à tela inicial".
