<p align="center">
  <img src="./logo.png" width="140" alt="Logo do Huginn">
</p>

<h1 align="center">Huginn</h1>

<p align="center">
  <em>Datatables ActiveRecord performantes e busca tolerante a erros.</em><br>
  Huginn é o corvo de Odin que representa o pensamento e a memória — o companheiro de Muninn.
</p>

<p align="center">
  <a href="./README.md">🇺🇸 English</a> · 🇧🇷 Português
</p>

O Huginn é uma camada de consulta leve para Rails que transforma uma requisição de datatable bruta em um **count enxuto, um subconjunto paginado e um único preload** — em vez de um JOIN enorme materializado em memória. Também traz um construtor de busca *fuzzy* para PostgreSQL (similaridade `pg_trgm` com `unaccent` e fallback `ILIKE`) tolerante a erros de digitação e acentuação.

## Destaques

- **Execução em duas fases** — filtros/orders/ranges de associação se tornam subqueries resolvidas por reflexão, e o `preload` é feito **somente no subconjunto paginado**.
- **Counts enxutos** — `COUNT(DISTINCT pk)` através de uma relation restrita, sem materialização de JOINs.
- **Ordenação/filtro seguros contra SQL injection** — toda referência de coluna é resolvida via reflexão do Arel, nunca interpolada como string.
- **Busca tolerante a acentos/typos** — similaridade `pg_trgm` OU `unaccent+ILIKE`, com cadeia de fallback configurável.
- **Convenções do Rails** — funciona com `ActionController::Parameters`, Railtie inclui ambos os concerns automaticamente (desligável), zero boilerplate.

## Desenvolvimento

O `Gemfile` raiz mantém apenas as ferramentas (rspec, appraisal, pry) — cada série suportada do Rails vive num Appraisal próprio. Para rodar a suíte:

```
bundle install
bundle exec appraisal install        # gera os gemfiles/*.gemfile + resolve
bundle exec appraisal rspec          # roda a matrix completa (Rails 7.1/7.2/8.0)
bundle exec appraisal rails-8.0 rspec   # ou uma série isolada
bundle exec rake matrix              # atalho para a matrix completa
```

Um `bundle exec rspec` isolado precisa de ambiente ativo: `export BUNDLE_GEMFILE=gemfiles/rails_8.0.gemfile`.

## Versões suportadas

| Componente | Escopo |
|---|---|
| Ruby | `>= 3.0` (sem teto — Rails 8 + Ruby 4 suportados) |
| Rails | `>= 7.1, < 9` |
| Pagy | `>= 6` (dependência runtime, instalada automaticamente) |
| PostgreSQL | busca pg_trgm / unaccent / ILIKE; degrada sem eles na ausência |

A suíte é verificada contra **Rails 7.1, 7.2 e 8.0** em várias Rubies suportadas via [Appraisal](https://github.com/thoughtbot/appraisal). Rode a matrix completa localmente:

```
bundle exec appraisal install
bundle exec appraisal rspec
```

Os `gemfiles/*.gemfile` são gerados pelo Appraisal (commitados); os arquivos `.lock` deles **não** são — cada célula da CI resolve pelo seu par Ruby/Rails.

## Instalação

```ruby
gem "huginn"
```

## Configuração

```ruby
# config/initializers/huginn.rb
Huginn.configure do |config|
  # :pg_trgm  (recomendado) — similaridade trigram OU unaccent+ILIKE
  # :unaccent               — somente unaccent + ILIKE
  # :simple                 — LIKE simples
  config.search_strategy = :pg_trgm

  config.fuzzy_threshold = 0.3   # cutoff de similarity() usado por :pg_trgm
  config.pagy_items = 10         # tamanho de página padrão
  config.pagy_max_items = 500    # teto máximo de per_page
end
```

## Railtie (include automático)

Por padrão, o Railtie inclui `Huginn::Datatable` e `Huginn::Searchable` em toda `ActiveRecord::Base`. Você **não** precisa de `include`, a menos que opte seletivamente:

```ruby
Huginn.configure { |c| c.auto_include_datatable = false; c.auto_include_searchable = false }
```

## Uso — datatable

```ruby
class Plano < ApplicationRecord
  # Datatable + Searchable são incluídos automaticamente via Railtie
end
```

```ruby
result = Plano.datatable(
  params,
  allowed_paths: [:grupo, { operadora: [:pessoa] }], # associações que filtros/orders podem usar
  includes: [{ operadora: { pessoa: [:endereco, :contatos] } }] # preload somente na página
)

result[:total_count] # Integer (count enxuto COUNT DISTINCT pk)
result[:data]        # ActiveRecord::Relation (paginada + preloaded)
```

Parâmetros suportados:

| Parâmetro | Comportamento |
|---|---|
| `page`, `per_page` | Paginação (limitada a `pagy_max_items`) |
| `search` | Delega para `Huginn::Searchable.search` |
| `filters` | Hash / Array de hashes / pares -> condições exatas ou `IN` (`"col" => "null"` → `IS NULL`) |
| `range_data` | `{ "created_at" => ["2024-01-01", "2024-12-31"] }` — ranges de datas ou numéricos |
| `orders` | `[{ "pessoa.nome" => "desc" }]` — colunas simples ou de associação |

### Ordenação/filtro com associação

Qualquer referência `column` **ou** `associacao.column` é validada e mapeada para a tabela refletida real:

```ruby
Plano.datatable({ orders: [{ "operadora.pessoa.nome" => "asc" }] }, allowed_paths: [{ operadora: :pessoa }])
```

> Filtros/ranges e order de associação usam subqueries resolvidas por reflexão (veja a seção "Allowlist de associações" abaixo). A relation principal permanece única e o count é `COUNT(DISTINCT pk)`.

## Allowlist de associações (`allowed_paths`)

Para proteger o schema e manter a consulta enxuta, o `datatable` não materializa `left_joins` para filtrar/ordenar por associações. Em vez disso:

- **Filtros/ranges** de colunas de associação viram subqueries `pk IN (SELECT DISTINCT pk …)` — a relation principal nunca é multiplicada;
- **Ordenação** por coluna de associação usa uma *subquery escalar correlacionada* (`ORDER BY (SELECT … ORDER BY col ASC LIMIT 1)`), determinística mesmo para `has_many` (menor valor);
- **Apenas as associações autorizadas** podem ser referenciadas. Passe `allowed_paths:` com as associações que o chamador pode usar na query:

```ruby
result = Plano.datatable(
  params,
  allowed_paths: [:grupo, { operadora: :pessoa }],  # associações que filtros/orders podem usar
  includes:      [{ operadora: { pessoa: [:endereco, :contatos] } }] # preload somente da página
)
```

- **Deny-all por padrão**: sem `allowed_paths:`, nenhuma associação é autorizada para filtro/ordem — apenas colunas da própria tabela.
- `allowed_paths:` aceita os mesmos formatos do Rails (`:symbol`, `"string"`, Hash aninhado, Array misto). Nomes de tabela (`"companies"`) são reconhecidos como a associação correspondente (`:company`).
- `includes:` continua independente do `allowed_paths:`: ele só controla o **preload** dos dados na página paginada.

## Aliases de campos & proteção do schema

APIs públicas não deveriam expor o schema do banco. Declare um mapeamento de **nomes públicos** para colunas/tabelas reais com `huginn_attributes`:

```ruby
class User < ApplicationRecord
  # Nome de API pública -> coluna/tabela real (nome da associação ou nome da tabela)
  huginn_attributes(
    name:         "users.name",
    email:        "users.email",
    created_at:   "users.created_at",
    company_name: "companies.name"   # coluna de associação, resolvida via subquery
  )
end
```

- Os chamadores filtram/ordenam/rangeiam apenas pelos aliases: `{ filters: { company_name: "Acme Corp" } }`, `{ orders: [{ company_name: "asc" }] }`.
- **Estrito por padrão**: campos fora do mapeamento são silenciosamente rejeitados (nunca chegam ao SQL e nunca são respondidos). O schema permanece oculto para consumidores da API.
- Aliases de associação (`companies.name`) resolvem pela associação **somente se ela estiver autorizada em `allowed_paths:`** (a mesma allowlist se aplica aos aliases).
- Sem `huginn_attributes`, o modelo **cai de volta** para colunas simples/refletidas (`name`, `company.name`).
- Sem `allowed_paths:`, aliases de associação são **negados**; apenas colunas simples podem ser usadas.
- `huginn_attributes({ ... }, strict: false)` mantém a tradução de aliases, mas também aceita colunas cruas.

## Uso — search

```ruby
# Padrão: busca em toda coluna :string / :text do modelo.
Person.search("kayky")            # tolerante a typos e acentos, sem distinção de caixa

# Sobrescreva quais colunas pesquisar (inclusive através de associações):
class Person < ApplicationRecord
  searchable_columns :name, company: [:name, :cnpj]
end

Person.search("globex")                            # encontra company.name via left_join
Person.search("kayky", distinct: false)            # desativa o DISTINCT implícito
```

`Huginn::Datatable` reutiliza `Huginn::Searchable.search` automaticamente quando o modelo responde a `search`.

## Eficiência da query

```
fase 1  construir a relation      subqueries (pk IN … / ORDER BY (SELECT …)) + search + filters + order   (sem dados em memória)
fase 2  count                     SELECT COUNT(DISTINCT "<pk>") ... (subquery, indexada por pk)
        paginate                  offset / limit
        preload                   SELECT ... WHERE id IN (subset)        (2ª query leve)
```

Para um datatable de `Plano` com `includes:` profundos, isso são exatamente **2 queries extras** na página pequena em vez de um JOIN enorme.

## Arquitetura

```
lib/huginn.rb                       entry, Huginn.configure, Huginn.instrument
lib/huginn/configuration.rb         search_strategy, fuzzy_threshold, pagy_*
lib/huginn/railtie.rb               auto-inclui os concerns no ActiveRecord
lib/huginn/datatable.rb             Huginn::Datatable (agregador)
lib/huginn/datatable/datatable.rb   o Concern do datatable
lib/huginn/datatable/validator.rb   validação de coluna/associação + resolução Arel
lib/huginn/datatable/association_path.rb   resolução de cadeias de associação + subqueries
lib/huginn/datatable/allowed_paths.rb      expansão/autorização da allowlist `allowed_paths:`
lib/huginn/datatable/filter_normalizer.rb  normalização funcional de params
lib/huginn/datatable/paginator.rb  count enxuto, paginação, preload isolado
lib/huginn/searchable.rb            Huginn::Searchable (agregador)
lib/huginn/searchable/searchable.rb o Concern do search + DSL
lib/huginn/searchable/query.rb      construtor de busca tolerante (joins + OR)
lib/huginn/searchable/fuzzy.rb      predicados pg_trgm / unaccent / simple
```

## Instrumentação

`Huginn.instrument` envolve eventos de `ActiveSupport::Notifications` no namespace `huginn` (ex.: `datatable.call.huginn`). Assine com `ActiveSupport::Notifications.subscribe(/\.huginn/)`.

## Licença

MIT