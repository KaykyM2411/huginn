## Changelog

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