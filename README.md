# Textpattern on Rails

Um clone do [Textpattern CMS](https://textpattern.com/) 4.9 escrito em Ruby on Rails 8.1
com SQLite. O objetivo é **compatibilidade**: os mesmos templates (páginas, forms, estilos
e temas no formato de diretório do Textpattern), a mesma linguagem de tags `<txp:… />`,
os mesmos esquemas de URL e o mesmo painel administrativo (`/textpattern/index.php?event=…`),
de modo que um tema ou um site do Textpattern funcione aqui sem alterações.

A compatibilidade não é só declarada: ela é medida contra o Textpattern real
(PHP 8.3 + MariaDB em Docker), comparando as respostas byte a byte — veja
[Teste diferencial](#teste-diferencial-contra-o-textpattern-real).

## Requisitos

- Ruby 4.0 (veja `.ruby-version`) e Bundler
- SQLite 3
- ImageMagick (`magick` ou `convert`), opcional, para miniaturas automáticas
- Docker, apenas para o teste diferencial

## Primeiros passos

```bash
bundle install
bin/rails db:prepare
bin/rails server
```

Abra <http://localhost:3000/textpattern/>: na primeira visita aparece o instalador, que
cria o site, o tema padrão, seções, categorias, conteúdo de exemplo e a conta de
publicador. O site público fica em <http://localhost:3000/>.

Testes:

```bash
bin/rails test
```

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
  jQuery e jQuery UI são carregados como no Textpattern, para temas e plugins.
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

Plugins são escritos em Ruby (plugins PHP do Textpattern têm os metadados importados,
mas o código PHP não pode rodar). Exemplo:

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
| `db/themes/default/` | tema público instalado pelo instalador |
| `script/oracle/` | teste diferencial contra o Textpattern real |

## Teste diferencial contra o Textpattern real

`script/oracle/` sobe o Textpattern 4.9 (ramo `4.9.x`) com PHP 8.3 e MariaDB em Docker
na porta 8081 e este projeto na porta 3001, carrega o mesmo conteúdo nos dois bancos e
compara as respostas:

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
`debug`. Na última execução foram 634 comparações, todas idênticas.

Também é possível comparar URLs avulsas (`ruby script/oracle/diff.rb /about/ '/?q=x'`),
seguir links (`--crawl=N`), mudar preferências nos dois lados
(`script/oracle/setup.sh pref permlink_mode messy`) ou usar outro tema
(`THEME=/caminho/do/tema script/oracle/setup.sh reload`). As diferenças ficam em
`tmp/oracle/diffs/`. Os comportamentos encontrados dessa forma estão fixados em
`test/lib/txp/fidelity_test.rb`, que roda sem Docker.

## Fidelidade, inclusive aos defeitos

Onde o Textpattern 4.9 se comporta de forma inesperada, o clone reproduz o que ele
realmente faz, não o que a documentação sugere, porque é isso que os templates
existentes encontram. Exemplos:

- `<txp:comments_help />` e `<txp:popup_comments />` são tags desconhecidas no 4.9
  (a primeira está registrada para um método inexistente, a segunda nunca é registrada).
- `<txp:if_request>` com o tipo padrão (`request`) só enxerga parâmetros depois que o
  PHP criou `$_REQUEST`, o que acontece quando alguma classe de tag é carregada sob
  demanda (imagens, arquivos, links, comentários…) antes dela na página.
- Um `<txp:yield />` dentro de um form chamado como tag vazia (`<txp::box />`) produz `1`.
- Em sites `live`, tags usadas fora de contexto continuam com um contexto vazio em vez
  de serem abortadas (por exemplo, `<txp:comments_form />` fora de um artigo mostra
  "Commenting is closed for this article.").
- O `<id>` das entradas de links no Atom usa o esquema `https?://` literal do
  `atom.php`.

Diferenças deliberadas: código PHP (`<txp:php>`, plugins PHP) não é executado — com
`allow_page_php_scripting` desligado (o padrão) a saída é a mesma do Textpattern — e
o banco é SQLite em vez de MySQL/MariaDB.

## Licença

O Textpattern é distribuído sob a GNU GPL versão 2. Este projeto porta a lógica do
Textpattern e inclui arquivos dele (idiomas, `mode.ini`, textos de ajuda e o tema
administrativo Hive), portanto também é distribuído sob a GPL v2 — veja `LICENSE`.
jQuery e jQuery UI (em `public/textpattern/vendors/`) usam a licença MIT.
