## Changelog

### Unreleased

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