## Changelog

### Unreleased

#### 0.3.0

- **New `:full_text` search strategy** — PostgreSQL full text search over lexemes (`public.f_tsvector(col) @@ plainto_tsquery('portuguese'::regconfig, 'term')`), so morphological variants match (e.g. "compras" finds "compra"). Blind to typos, unlike `:pg_trgm`. Uses a GIN tsvector index when the `fts_function` wrapper (IMMUTABLE, dictionary pinned) exists; degrades gracefully to unaccent+ILIKE otherwise.
- `search_strategy:` now accepts **a single symbol or an Array of them**; multiple strategies are combined with **OR** (a row matches if any strategy matches), e.g. `[ :pg_trgm, :full_text ]` to get typo tolerance plus stemming.
- New `fts_dictionary:` (default `"portuguese"`) and `fts_function:` (default `"public.f_tsvector"`) configurations, mirroring `unaccent_function`.
- New generator **`rails g huginn:fts_indexes [Model...]`** scaffolds a migration that creates the IMMUTABLE `public.f_tsvector` wrapper (with `--dictionary`) and GIN tsvector indexes on every `:string`/`:text` column of the Searchable models, including association-scoped ones.
- `searchable_columns columns: []` is now honored — an empty array means "search only the declared associations", no longer falling back to the model's own string/text columns.
- Specs for the `Configuration` normalization surface (defaults + `search_strategy` symbol/array shapes).

- Association-scoped `search` now matches through **primary-key semi-join subqueries** (`pk IN (SELECT DISTINCT pk FROM <base> JOIN <chain> WHERE <fuzzy>)`) instead of `left_joins` — one subquery per distinct association chain, combined with OR. The base relation never joins, so the count is a plain `COUNT(*)`.

#### 0.2.0

- **Breaking:** `:pg_trgm` search now uses the PostgreSQL `%` operator (`UNACCENT(col) % UNACCENT('term')`), driven by the **indexable** operator instead of a bare `similarity()` comparison. A `gin_trgm_ops` GIN index on `UNACCENT(col)` is used when present (BitmapOr over the same index with the ILIKE branch); without it, results stay correct via sequential scan.
- **Breaking:** removed the `fuzzy_threshold` configuration. The similarity cutoff is now the PostgreSQL GUC `pg_trgm.similarity_threshold` (default `0.3`, same as the old gem default) — tune with `SELECT set_limit(...)` / `SET pg_trgm.similarity_threshold`.
- New `unaccent_function` configuration (default `"unaccent"`): the unaccent function used in search SQL. Point it at an `IMMUTABLE` wrapper to make GIN trigram indexes usable (the pg builtin `unaccent()` is `STABLE` on PG 13+ and cannot be indexed directly).
- New generator `rails g huginn:trigram_indexes [Model...]` scaffolds a migration that creates an `IMMUTABLE public.f_unaccent` wrapper and `CREATE INDEX ... USING gin (public.f_unaccent(col) gin_trgm_ops)` for Searchable models (all `:string`/`:text` columns, including association-scoped ones).
- Runtime dependency on Pagy declared in the gemspec (`pagy >= 6`) — consumers install it automatically (datatable pagination is not test-only anymore).
- Supported Rails floor bumped to **7.1** (`>= 7.1, < 9`); Ruby `>= 3.0` without an upper bound (Rails 8 + Ruby 4 supported).
- Appraisals now cover **Rails 7.1 / 7.2 / 8.0** (was 6.1/7.0/7.1) with generated `gemfiles/*.gemfile`; CI matrix runs every Rails over supported Rubies (3.0 up to 4.0, including Rails 8 on Ruby 4.0).
- `allowed_paths:` allowlist: associações que filtros/orders/range podem usar.
  - **Deny-all por padrão** — sem `allowed_paths:`, apenas colunas da própria tabela.
  - Accepts Rails shapes (Symbol/String/Hash/Array); table names map to the reflection.
  - Ordenação por associação via subquery escalar correlacionada determinística (`ORDER BY (SELECT … LIMIT 1)`); filtros/range via `pk IN (SELECT DISTINCT pk …)`.
  - `allowed_paths` also gates `huginn_attributes` association aliases.
- `huginn_attributes` mapping: public API aliases for datatable fields, hiding the database schema.
  - Strict by default — fields outside the mapping are silently rejected.
  - Alias targets accept association names (`company.name`) or table names (`companies.name`).
  - `huginn_attributes({ ... }, strict: false)` for a translation-only mapping; plain/reflected columns remain the fallback when no mapping is set.

### 0.1.0 — 2026-08-05

- Initial release of the `Huginn` gem.
- `Huginn::Datatable` concern: two-phase (filter → count/paginate/preload) datatable execution.
  - `left_joins` for filtering/ordering; values are never string-interpolated.
  - Lean `COUNT(DISTINCT pk)` via subquery.
  - `preload` applied *only* to the final paginated subset.
  - DISTINCT applied only when a joined association multiplies rows.
- `Huginn::FilterNormalizer`: fluid, tolerant normalization of filter payloads (Parameters / Hash / Array / pairs).
- `Huginn::Datatable::Validator`: validation + Arel resolution of plain and association-scoped columns.
- `Huginn::Datatable::Paginator`: enxuto count and pagination (Pagy), `preload` isolation.
- `Huginn::Searchable`: tolerant full-text search over PostgreSQL.
  - `:pg_trgm` (similarity OR unaccent+ILIKE), `:unaccent`, `:simple` strategies, runtime degrade when extensions missing.
  - Default: all `:string`/`:text` columns; overridable via `searchable_columns`.
  - Association-scoped columns reached through `left_joins`.
- Railtie auto-includes both concerns into `ActiveRecord::Base` (configurable), mirrors the `muninn` gem layout (version, configuration, Appraisals, CI matrix, `spec/dummy`).