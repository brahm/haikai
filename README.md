# Haikai

Um CMS criado em Ruby on Rails 8.1, com SQLite, que buscou paridade de funcionalidades com
o [Textpattern CMS](https://textpattern.com/) 4.9 para suportar o modelo de temas dele: os
mesmos templates (páginas, forms, estilos e temas no formato de diretório do Textpattern), a
mesma linguagem de tags `<txp:… />` e os mesmos esquemas de URL, de modo que um tema do
Textpattern funcione aqui sem alterações.

Alcançada a paridade (tag `v1.0-paridade`), o projeto segue seu próprio caminho. O
compromisso com o Textpattern é o **lado público**; o painel administrativo e o resto podem
divergir, veja [Compatibilidade](#compatibilidade-com-o-textpattern). Sites Textpattern
existentes não são migrados ([o que fica de fora](#o-que-fica-de-fora)). É um projeto
independente, sem vínculo com o projeto Textpattern.

A compatibilidade não é só declarada: ela é medida contra o Textpattern real
(PHP 8.3 + MariaDB em Docker), comparando as respostas byte a byte — veja
[Teste diferencial](#teste-diferencial-contra-o-textpattern-real). Os bugs do Textpattern
4.9 encontrados nessa comparação foram corrigidos; veja [a lista](#bugs-do-textpattern-49-corrigidos).

## Por que este projeto existe

Criei o Haikai por dois motivos. O primeiro é integrar ao próprio CMS recursos que,
no Textpattern, só existem como plugins. O segundo é que sou programador Ruby on Rails, e
não PHP, o que me impedia de colaborar com o projeto original.

## Requisitos

- Ruby 4.0 (veja `.ruby-version`) e Bundler
- SQLite 3
- ImageMagick (`magick` ou `convert`), opcional, para miniaturas automáticas
- `sendmail` ou um servidor SMTP, para os e-mails (veja [E-mail](#e-mail))
- Docker, para a imagem de produção e o teste diferencial

## Primeiros passos

```bash
bundle install
bin/rails db:prepare
bin/rails server
```

O `db:prepare` cria o banco e instala o site, como o instalador do Textpattern: tema
padrão, seções, categorias, conteúdo de exemplo e a conta de publicador `admin`, cuja
senha aparece no terminal (`ADMIN_USER`, `ADMIN_PASS`, `ADMIN_EMAIL`, `SITE_NAME`,
`SITE_LANG` e `SITE_URL` mudam esses valores). Para usar o instalador web, crie o banco vazio com
`bin/rails db:create db:schema:load`: ele aparece na primeira visita ao painel.

O painel fica em <http://localhost:3000/textpattern/> (o endereço do Textpattern; `/admin`
também leva até lá, a menos que o site tenha uma seção chamada "admin") e o site público
em <http://localhost:3000/>.

Testes:

```bash
bin/rails test   # só os testes
bin/ci           # RuboCop, bundler-audit, Brakeman, testes e seeds
```

Os avisos do Brakeman revisados e aceitos ficam em `config/brakeman.ignore`, cada um com
a justificativa.

## O que está implementado

**Linguagem de templates**

- Tokenizador e parser portados de `txp_tokenize()`/`parse()`/`processTags()`:
  `<txp:else />`, atributos entre aspas simples processados como tags, tags curtas
  `<txp::form />` e `<prefixo::tag />`, segunda passagem (`secondpass`) e sandbox.
- As 171 tags registradas pelo Textpattern 4.9, com seus atributos, e os atributos
  globais `wraptag`, `break`, `class`, `escape`, `trim`, `replace`, `default`, `limit`,
  `offset`, `sort`, `breakby`, `breakform`, `wrapform`, `not`, `evaluate`, `variable`,
  `label`, `labeltag` e `html_id`.
- `filterAtts()` (listas de artigos, busca, paginação, ordenação, campos
  personalizados), `<txp:evaluate>` com XPath, variáveis, `yield`, formulários de
  comentário com nonce, feeds RSS/Atom, downloads de arquivos, imagens e miniaturas.
- Os oito modos de permalink (`messy`, `section_title`, `id_title`,
  `year_month_day_title`, `section_id_title`, `title_only`, `section_category_title`,
  `breadcrumb_title`), páginas de erro `error_<código>`/`error_default`,
  `Last-Modified`/`ETag`/304 e o resumo de trace dos modos `testing`/`debug`.
- Forms de tipos personalizados servidos como arquivos com `?f=`, como no
  `index.php` do Textpattern: com um tipo definido em Preferences → Advanced options →
  "Custom form template types" (por exemplo `[js]` com
  `mediatype="application/javascript"`), um form `app.js` desse tipo fica em
  `/?f=app.js`, e `/?f=a.js,b.js` junta vários do mesmo tipo.
  `<txp:component form="app.js" format="script" />` gera esses endereços.
- Funções do MySQL usadas em templates (`FIELD`, `FIND_IN_SET`, `DATE_FORMAT`,
  `UNIX_TIMESTAMP`, `REGEXP`…) registradas no SQLite, para que atributos como
  `sort="FIELD(ID, 3, 1)"` funcionem.

**Painel administrativo**

- Todos os painéis do Textpattern: Write, Articles, Images, Files, Links, Comments,
  Categories, Sections, Pages, Forms, Styles, Themes, Preferences, Users, Languages,
  Plugins, Visitor logs, Diagnostics e o construtor de tags; recuperação de senha,
  papéis e privilégios do Textpattern.
- A marcação segue a do Textpattern, então temas administrativos do Textpattern
  funcionam: o tema padrão é o **Nova** (próprio) e o **Hive**, tema oficial do
  Textpattern, vem incluído sem modificações (Admin → Preferences → Admin-side theme).
  jQuery e jQuery UI são carregados como no Textpattern, para temas e plugins. O painel
  fica fora do [compromisso de compatibilidade](#compatibilidade-com-o-textpattern),
  então isso pode mudar.
- Importação e exportação de temas no formato de diretório do Textpattern
  (`manifest.json`, `pages/`, `forms/<tipo>/`, `styles/`) e em `.zip`.
- Ajuda contextual (os `?` ao lado dos campos) com os textos oficiais do Textpattern.

**Idiomas**

- Os 57 arquivos de idioma do Textpattern 4.9 (`config/textpacks/*.ini`) com a mesma
  semântica de `gTxt()`: no site público só as seções `public` e `common`, fora do modo
  live as mensagens de depuração de `mode.ini`, e as palavras reservadas (`yes`, `no`,
  `on`…) guardadas como `txp_yes` etc. Os poucos textos exclusivos deste port ficam em
  `config/textpacks/extra/` (inglês e português).
- Textpacks podem ser importados pelo painel Languages (formato `.ini` ou textpack
  legado) e ficam na tabela `txp_lang`, como no Textpattern.

**Plugins**

Plugins são escritos em Ruby; plugins PHP não rodam (veja
[o que fica de fora](#o-que-fica-de-fora)). Exemplo:

```ruby
# name: abc_hello
# version: 1.0
# description: Diz olá

tag :abc_hello do |txp, atts, thing|
  "Olá, #{txp.txpspecialchars(atts['name'] || 'mundo')}!"
end

callback "comment.saved" do |comment:, **|
  Rails.logger.info("Novo comentário #{comment.id}")
end

admin_tab "extensions", "abc_stats", "Estatísticas" do |admin|
  "<h1 class='txp-heading'>Estatísticas</h1><p>#{Article.count} artigos</p>"
end
```

## Compatibilidade com o Textpattern

Até a tag `v1.0-paridade` este projeto era um clone do Textpattern 4.9, painel incluído.
Dali em diante o compromisso com o Textpattern fica restrito ao lado público.

**Continua garantido:**

- Templates: o parser e as 171 tags do Textpattern 4.9, com seus atributos. Um template
  gera a mesma página que geraria no Textpattern 4.9, com os mesmos cabeçalhos de cache,
  e o mesmo vale para feeds, comentários e downloads.
- Temas no formato de diretório do Textpattern, nos dois sentidos: temas do Textpattern
  funcionam aqui, e temas feitos aqui que só usem tags do Textpattern funcionam lá.
- As URLs públicas: os oito modos de permalink, feeds, downloads, `css.php` e `?f=`.
- Os nomes de tabelas e colunas que templates citam em atributos, como
  `sort="Posted desc"` ou `sort="custom_1 asc"`.

Tags e atributos novos podem ser acrescentados. A saída de uma tag que já existe só muda
de forma registrada: os [bugs do Textpattern corrigidos](#bugs-do-textpattern-49-corrigidos)
e as mudanças deliberadas, que entram no README com um teste e ficam fora das rotas do
[teste diferencial](#teste-diferencial-contra-o-textpattern-real). O teste diferencial
continua sendo a prova deste compromisso.

**Pode divergir:**

- O painel administrativo: telas, marcação e URLs (`/textpattern/index.php?event=…`).
  Temas administrativos do Textpattern, como o Hive, funcionam hoje, mas sem garantia.
- As preferências, o resto do esquema do banco e o código interno.

## O que fica de fora

Estes recursos do Textpattern 4.9 ficam de fora por decisão, não por falta de tempo:
não estão nos planos.

- **Código PHP.** Plugins PHP não rodam: ao instalar um, os metadados (nome, versão,
  autor, descrição e ajuda) são importados, mas o plugin fica desativado e sem efeito, e
  o código PHP é guardado só como referência para quem for convertê-lo para Ruby.
  `<txp:php>` também não executa nada: com "Allow PHP in pages?" e "Allow PHP in
  articles?" desligados (o padrão) a saída é a mesma do Textpattern; ligados, a tag não
  gera saída e mostra um aviso nos modos `testing` e `debug`. A preferência "Plugin
  cache directory path" e o `pre_publish_script` do `config.php` não têm equivalente.
- **XML-RPC.** Não há o servidor de `rpc/`, usado por editores de blog pelas APIs
  Blogger, MetaWeblog e Movable Type. A preferência "Enable XML-RPC server?" não existe
  aqui, e `<txp:rsd />` (obsoleta no 4.9) nunca gera o link para o servidor.
- **Multi-site.** Não há a estrutura `sites/` do Textpattern (vários sites sobre o mesmo
  núcleo, cada um com seu `config.php`, `admin/` e `public/`), nem `table_prefix` ou o
  painel em outro domínio (`admin_url`). Cada instância serve um site, com seu banco e o
  painel em `/textpattern/`. Para vários sites, rode uma instância por site (com a imagem
  Docker, um container com volumes próprios para cada um).
- **Importação.** O painel Import do Textpattern (WordPress, Movable Type, Blogger, b2)
  saiu na versão 4.6, e sites Textpattern existentes não são migrados: nada aqui lê
  bancos ou dumps MySQL/MariaDB. De outro Textpattern só vêm os temas, pelo painel Themes
  (copie a pasta do tema para `public/themes/` ou envie um `.zip`). Artigos, imagens,
  arquivos, links, comentários, usuários e preferências precisam ser criados aqui.
- **MySQL/MariaDB.** O banco é sempre SQLite.

## E-mail

Os e-mails (notificação de comentários, recuperação de senha, novas contas) seguem as
preferências de e-mail do Textpattern (Preferences → Mail): com "Use enhanced mail
features" ligado e servidor e porta SMTP preenchidos, o envio é por SMTP (usuário,
senha e segurança `SSL`, `TLS` ou nenhuma); senão, pelo `sendmail` local. O remetente é
o "Publisher email" com o nome do site (ou `no-reply@<domínio do site>`), "SMTP envelope
sender address" vira o remetente de envelope e "Use ISO-8859-1 encoding in emails"
converte as mensagens.

Como as constantes `SMTP_*` do `config.php` do Textpattern, as variáveis de ambiente
`SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASS` e `SMTP_SECTYPE` têm precedência
sobre as preferências (o campo fica bloqueado no painel). Assim a senha não precisa
ficar no banco.

Os links enviados por e-mail (redefinição de senha, ativação de conta) usam a URL do site
(Preferences → Site → "Site URL"), nunca o cabeçalho `Host` da requisição, que qualquer um
pode forjar para desviar um link de redefinição para outro servidor. O instalador web pede
essa URL, já preenchida com o endereço em uso, como o do Textpattern; num site instalado pela
linha de comando ela vem de `SITE_URL` ou, na falta dela, do endereço usado no primeiro
login, que o painel mostra nesse momento para ser conferido. Enquanto não houver URL do
site, pedidos de redefinição de senha não enviam e-mail (fica um aviso no log).

## Produção com Docker

O `Dockerfile` gera uma imagem de produção com ImageMagick. Os dados do site ficam em
volumes: o banco (`/rails/storage/production.sqlite3`), os arquivos para download
(`/rails/files`), as imagens enviadas (`/rails/public/images`) e os temas exportados
pelo painel (`/rails/public/themes`).

```bash
docker build -t haikai .
docker run -d --name haikai -p 80:3000 \
  -e SECRET_KEY_BASE="$(bin/rails secret)" \
  -v txp_storage:/rails/storage -v txp_files:/rails/files \
  -v txp_images:/rails/public/images -v txp_themes:/rails/public/themes \
  haikai
```

- `SECRET_KEY_BASE` assina os cookies: gere uma vez e guarde (ou passe
  `RAILS_MASTER_KEY` com a chave de `config/credentials.yml.enc`).
- A imagem espera um proxy com HTTPS na frente e redireciona HTTP para HTTPS. Para
  testar localmente em HTTP, acrescente `-e RAILS_FORCE_SSL=false`.
- Na primeira partida o banco é criado e o site instalado; a senha do usuário `admin`
  aparece em `docker logs haikai` (ou defina `ADMIN_USER`, `ADMIN_PASS`,
  `ADMIN_EMAIL`, `SITE_NAME` e `SITE_LANG` com `-e`). Nas seguintes, só as migrações
  pendentes rodam; elas também levam as correções do tema padrão aos templates que o site
  não editou.
- Passe o endereço público do site em `-e SITE_URL=example.com`; sem ele, vale o endereço
  do primeiro login no painel, que por isso deve ser feito pelo domínio do site.
- A imagem não tem `sendmail`: para enviar e-mails, passe as variáveis `SMTP_*` e ligue
  "Use enhanced mail features" em Preferences → Mail (veja [E-mail](#e-mail)).
- Diretórios do host montados no lugar dos volumes precisam pertencer ao usuário 1000,
  que roda a aplicação.
- Se `img_dir`, `skin_dir` ou `file_base_path` forem alterados nas preferências, os
  volumes precisam acompanhar.

### Backup

`bin/rails txp:backup` grava em `storage/backups/` (ou em `BACKUP_DIR`) um
`txp-<data>.tar.gz` com uma cópia consistente do banco, feita com o site no ar, e os
diretórios de arquivos, imagens e temas; ficam as 7 cópias mais recentes (`BACKUP_KEEP`).
Com Docker, guarde as cópias num diretório do host, fora dos volumes do site: acrescente
`-v /srv/txp-backups:/rails/backups -e BACKUP_DIR=/rails/backups` ao `docker run` (com
SELinux, `/srv/txp-backups:/rails/backups:Z`; o diretório precisa pertencer ao usuário
1000) e agende o backup no crontab do host:

```bash
0 3 * * * docker exec haikai bin/rails txp:backup
```

Para restaurar, pare o site: `bin/rails txp:restore FILE=<arquivo>` guarda antes uma cópia do
estado atual e então devolve o banco e os diretórios. Com Docker, rode a restauração num
container temporário com os volumes do site:

```bash
docker stop haikai
docker run --rm --volumes-from haikai -e SECRET_KEY_BASE_DUMMY=1 -e BACKUP_DIR=/rails/backups haikai bin/rails txp:restore FILE=/rails/backups/txp-<data>.tar.gz
docker start haikai
```

## Estrutura

| Caminho | Conteúdo |
| --- | --- |
| `lib/txp/tokenizer.rb`, `lib/txp/renderer.rb` | parser e estado de cada requisição (`$pretext`, `$thisarticle`…) |
| `lib/txp/tags/*.rb`, `lib/txp/tags.rb` | biblioteca de tags e tabela de registro |
| `lib/txp/router.rb`, `lib/txp/publisher.rb` | resolução de URLs (`preText()`) e o ciclo da requisição pública |
| `lib/txp/feeds.rb` | RSS e Atom |
| `lib/txp/textpack.rb`, `lib/txp/pophelp.rb` | idiomas e ajuda contextual |
| `lib/txp/theme_io.rb` | importação/exportação de temas |
| `app/controllers/admin/`, `app/views/admin/` | painéis administrativos |
| `public/textpattern/admin-themes/` | temas administrativos (Nova, Hive) |
| `db/themes/default/` | tema público instalado pelo instalador (mudanças chegam aos sites existentes por migration, só nos templates não editados) |
| `script/oracle/` | teste diferencial contra o Textpattern real |

## Teste diferencial contra o Textpattern real

`script/oracle/` sobe o Textpattern 4.9 (o ramo `4.9.x` na revisão fixada em `TXP_REV`, no
`setup.sh`) com PHP 8.3 e MariaDB em Docker na porta 8081 e este projeto na porta 3001,
carrega o mesmo conteúdo nos dois bancos e compara as respostas:

```bash
script/oracle/setup.sh     # baixa o Textpattern, cria os containers e o conteúdo
script/oracle/check.sh     # roda a matriz completa
script/oracle/setup.sh stop
```

A matriz cobre o tema de comparação (`script/oracle/theme`, que usa todas as tags) nos
modos `live`, `testing` e `debug`; um rastreamento do site em cada um dos oito modos de
permalink; o fluxo de comentários (pré-visualização, envio com nonce, reenvio), com e sem
moderação; e o tema oficial `four-point-nine`. Em cada caso corpo **e** cabeçalhos de
cache (`Content-Type`, `Last-Modified`, `ETag`, `Cache-Control`, `Vary`…) precisam ser
idênticos; só são mascarados o nome do host, os tempos do trace e os backtraces do modo
`debug`. Só o lado público é comparado, que é o que o
[compromisso de compatibilidade](#compatibilidade-com-o-textpattern) garante; por isso a
matriz roda a cada mudança na renderização pública. Na última execução, contra o ramo
`4.9.x` na revisão `35e52d9`, foram 586 comparações, todas idênticas (as divergências
registradas ficam de fora; veja a seção seguinte).

Também é possível comparar URLs avulsas (`ruby script/oracle/diff.rb /about/ '/?q=x'`),
seguir links (`--crawl=N`), mudar preferências nos dois lados
(`script/oracle/setup.sh pref permlink_mode messy`) ou usar outro tema
(`THEME=/caminho/do/tema script/oracle/setup.sh reload`). As diferenças ficam em
`tmp/oracle/diffs/`. Os comportamentos encontrados dessa forma estão fixados em
`test/lib/txp/fidelity_test.rb`, que roda sem Docker.

## Bugs do Textpattern 4.9 corrigidos

Fora dos pontos abaixo, a saída é a do Textpattern 4.9. Estes defeitos do original
foram corrigidos; cada um tem um teste em `test/lib/txp/upstream_fixes_test.rb`, que
também descreve o que o Textpattern faz:

- `<txp:comments_help />` mostra o link de ajuda do Textile. No 4.9 ela está registrada
  para um método que não existe e resulta em "tag does not exist".
- `<txp:popup_comments />` funciona, junto com o modo de comentários em janela (*popup*)
  e o título "Comments on …" dessa janela. No 4.9 a tag nunca é registrada e o título
  depende de uma variável que nunca é definida.
- `<txp:if_request>` com o tipo padrão (`request`) sempre enxerga os parâmetros GET e
  POST. No 4.9 isso só acontece depois que o PHP cria `$_REQUEST`, o que depende de quais
  tags vieram antes na página.
- Um form chamado como tag vazia (`<txp::box />` ou `<txp:output_form form="box" />`)
  não tem conteúdo: `<txp:yield />` não imprime mais `1`, o atributo `default` passa a
  valer e `<txp:if_yield>` é falso.
- `<txp:comment_permlink />` vazio devolve a URL do comentário, como
  `<txp:permlink />`, e `<txp:link_to_next showalways="1" />` vazio não imprime nada.
  No 4.9, ambos imprimem `1`.
- Em sites `live`, tags usadas fora do seu contexto não imprimem nada. No 4.9 elas
  seguem com um contexto vazio e produzem marcação pela metade (como `<a id="c"></a>`)
  ou derrubam a página com um erro fatal do PHP. Nos modos `testing` e `debug` a
  mensagem de erro continua a mesma.
- `<txp:search_result_excerpt />` sem termo de busca não imprime nada (no 4.9,
  `&#8230;<strong></strong> &#8230;`).
- As tags de campos de comentário usadas fora de um `<txp:comments_form>` assumem os
  padrões dele (rótulos "Preview", "Submit"…, tamanhos), em vez de gerar avisos
  "Trying to access array offset on null" e botões sem rótulo.
- Avisos internos do PHP não vazam mais para as páginas nos modos `testing` e `debug`:
  o `strlen()` obsoleto de `<txp:if_different />` e o aviso de `mime_content_type()`
  para arquivos que faltam no disco.
- `?f=` com nomes que não correspondem a nenhum form de tipo personalizado responde 404.
  No 4.9 a resposta é 200, vazia e com o cabeçalho inválido `Content-Type: ; charset=utf-8`.
- Feeds de links: URLs relativas viram absolutas com o esquema e o host do site (o Atom
  do 4.9 escreve um `https?://` literal e escapa o `&` pela metade); o título usa o nome
  da categoria de links; uma categoria de links sem links gera um feed vazio em vez de
  404; e o cabeçalho `A-IM: feed` é reconhecido também quando `feed` vem primeiro.

O teste diferencial não passa por esses pontos: a página que usa todas as tags fora de
contexto só é comparada em `testing` e `debug`, e os rastreamentos pulam os feeds de
categorias de links.

Os recursos que ficam de fora de propósito (código PHP, XML-RPC, multi-site, importação
e MySQL) estão em [O que fica de fora](#o-que-fica-de-fora).

## Licença

O Textpattern é distribuído sob a GNU GPL versão 2. Este projeto porta a lógica do
Textpattern e inclui arquivos dele (idiomas, `mode.ini`, textos de ajuda e o tema
administrativo Hive), portanto também é distribuído sob a GPL v2 — veja `LICENSE`.
jQuery e jQuery UI (em `public/textpattern/vendors/`) usam a licença MIT.
