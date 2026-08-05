<h1 align="center">Huginn</h1>

<p align="center">
  <em>Performant, elegant ActiveRecord datatables and tolerant search.</em><br>
  Huginn is the raven of Odin that represents thought and remembrance — the mate of Muninn.
</p>

Huginn is a lightweight query layer for Rails that turns a raw datatable request into a **lean count, a paginated subset and one preload** — instead of a massive JOIN materialized in memory. It also ships a PostgreSQL fuzzy-search builder (`pg_trgm` similarity with `unaccent` and `ILIKE` fallback) that is tolerant to typos and accents.

## Highlights

- **Two-phase execution** — filtering/ordering over `left_joins`, then a lean count and `preload` **only on the paginated subset**.
- **Lean counts** — `COUNT(DISTINCT pk)` through a stripped relation instead of `COUNT(DISTINCT all_columns)` over the joins.
- **SQL injection safe ordering/filtering** — every column reference is resolved through Arel reflection, never string-interpolated.
- **Accent/typo tolerant search** — `pg_trgm` similarity OR `unaccent+ILIKE`, with a configurable fallback chain.
- **Rails conventions** — works with `ActionController::Parameters`, Railtie auto-includes both concerns (toggleable), zero boilerplate.

## Installation

```ruby
gem "huginn"
```

## Configuration

```ruby
# config/initializers/huginn.rb
Huginn.configure do |config|
  # :pg_trgm  (recommended) — trigram similarity OR unaccent+ILIKE
  # :unaccent               — unaccent + ILIKE only
  # :simple                 — plain LIKE
  config.search_strategy = :pg_trgm

  config.fuzzy_threshold = 0.3   # similarity() cutoff used by :pg_trgm
  config.pagy_items = 10         # default page size
  config.pagy_max_items = 500    # hard cap for per_page
end
```

## Railtie (automatic include)

By default the Railtie includes `Huginn::Datatable` and `Huginn::Searchable` into every `ActiveRecord::Base` model. You do **not** need `include` statements unless you opt in selectively:

```ruby
Huginn.configure { |c| c.auto_include_datatable = false; c.auto_include_searchable = false }
```

## Usage — datatable

```ruby
class Plano < ApplicationRecord
  # Datatable + Searchable are auto-included via Railtie
end
```

```ruby
result = Plano.datatable(
  params,
  joins:    [:grupo, { operadora: [:pessoa] }],          # used for filtering/ordering
  includes: [{ operadora: { pessoa: [:endereco, :contatos] } }] # preloaded on the page only
)

result[:total_count] # Integer (enxuto COUNT DISTINCT pk)
result[:data]        # ActiveRecord::Relation (paged + preloaded)
```

Supported params:

| Key | Behavior |
|---|---|
| `page`, `per_page` | Pagination (clamped to `pagy_max_items`) |
| `search` | Delegates to `Huginn::Searchable.search` |
| `filters` | Hash / Array of hashes / pairs -> exact or `IN` conditions (`"col" => "null"` → `IS NULL`) |
| `range_data` | `{ "created_at" => ["2024-01-01", "2024-12-31"] }` — date or numeric ranges |
| `orders` | `[{ "pessoa.nome" => "desc" }]` — plain or association-scoped columns |

### Scoped ordering / filtering

Any `column` **or** `association.column` reference is validated and mapped to its real reflected table:

```ruby
Plano.datatable({ orders: [{ "operadora.pessoa.nome" => "asc" }] }, joins: [{ operadora: :pessoa }])
```

> DISTINCT is applied only when a joined association multiplies rows (`has_many`/HABTM). Single-valued joins (`belongs_to`/`has_one`) never duplicate rows, so ordering by a joined column stays valid in PostgreSQL.

## Usage — search

```ruby
# Default: searches every :string / :text column of the model.
Person.search("kayky")            # typo/accent tolerant, case-insensitive

# Override which columns (including through associations) are searched:
class Person < ApplicationRecord
  searchable_columns :name, company: [:name, :cnpj]
end

Person.search("globex")                            # matches company.name via a left_join
Person.search("kayky", distinct: false)            # disable the implicit DISTINCT
```

`Huginn::Datatable` reuses `Huginn::Searchable.search` automatically when the model responds to `search`.

## Query efficiency

```
phase 1  build the relation          left_joins + search + filters + order   (no data in memory)
phase 2  count                       SELECT COUNT(DISTINCT "<pk column>") ... (subquery, pk-indexed)
          paginate                   offset / limit
          preload                    SELECT ... WHERE id IN (subset)        (2nd lightweight query)
```

For a `Plano` datatable with deep `includes:`, this is exactly **2 extra queries** on the small page instead of one enormous JOIN.

## Architecture

```
lib/huginn.rb                       entry, Huginn.configure, Huginn.instrument
lib/huginn/configuration.rb         search_strategy, fuzzy_threshold, pagy_*
lib/huginn/railtie.rb               auto-includes concerns into ActiveRecord
lib/huginn/datatable.rb             Huginn::Datatable (aggregator)
lib/huginn/datatable/datatable.rb   the datatable Concern
lib/huginn/datatable/validator.rb   column/association validation + Arel resolution
lib/huginn/datatable/filter_normalizer.rb  functional param normalization
lib/huginn/datatable/paginator.rb    lean count, pagination, isolated preload
lib/huginn/searchable.rb            Huginn::Searchable (aggregator)
lib/huginn/searchable/searchable.rb the search Concern + DSL
lib/huginn/searchable/query.rb      tolerant search builder (joins + OR)
lib/huginn/searchable/fuzzy.rb      pg_trgm / unaccent / simple predicates
```

## Instrumentation

`Huginn.instrument` wraps `ActiveSupport::Notifications` events under the `huginn` namespace (e.g. `datatable.call.huginn`). Subscribe with `ActiveSupport::Notifications.subscribe(/\.huginn/)`.

## License

MIT