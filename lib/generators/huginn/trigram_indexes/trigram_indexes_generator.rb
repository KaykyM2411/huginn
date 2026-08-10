# frozen_string_literal: true

require "rails/generators"
require "rails/generators/migration"
require "generators/huginn/searchable_columns"

module Huginn
  module Generators
    # Scaffolds a migration that creates the PostgreSQL expression GIN indexes
    # (gin_trgm_ops on an IMMUTABLE unaccent wrapper of the column) backing
    # Huginn::Searchable's :pg_trgm strategy for every model that includes
    # Huginn::Searchable.
    #
    #   rails g huginn:trigram_indexes                 # all Searchable models
    #   rails g huginn:trigram_indexes Person Product  # specific models
    #
    # The migration creates an IMMUTABLE public.f_unaccent(text) wrapper and
    # the GIN indexes. To make the search actually use them, point the gem at
    # the wrapper (the pg builtin unaccent() is STABLE on PG 13+ and cannot be
    # indexed directly):
    #
    #   Huginn.configure { |c| c.unaccent_function = "public.f_unaccent" }
    #
    # Indexes are only used when the :pg_trgm strategy is configured and the
    # pg_trgm/unaccent extensions are installed.
    class TrigramIndexesGenerator < Rails::Generators::Base
      include SearchableColumns

      source_root File.expand_path("templates", __dir__)

      argument :model_names, type: :array, default: [], desc: "Models to index (default: all Searchable models)"

      def copy_migration
        @entries = resolve_entries
        return if @entries.empty?

        migration_template(
          "add_huginn_trigram_indexes.rb.tt",
          "db/migrate/add_huginn_trigram_indexes.rb"
        )
      end
    end
  end
end