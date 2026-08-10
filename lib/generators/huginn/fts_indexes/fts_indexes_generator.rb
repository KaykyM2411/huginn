# frozen_string_literal: true

require "rails/generators"
require "rails/generators/migration"
require "generators/huginn/searchable_columns"

module Huginn
  module Generators
    # Scaffolds a migration that creates the PostgreSQL GIN tsvector indexes
    # (on an IMMUTABLE wrapper around to_tsvector) backing Huginn::Searchable's
    # :full_text strategy for every model that includes Huginn::Searchable.
    #
    #   rails g huginn:fts_indexes                       # all Searchable models
    #   rails g huginn:fts_indexes Person Product        # specific models
    #   rails g huginn:fts_indexes --dictionary english  # pick the dictionary
    #
    # The migration creates an IMMUTABLE public.f_tsvector(text) wrapper that
    # pins the configured dictionary and the GIN indexes. Point the gem at the
    # wrapper (to_tsvector itself is STABLE and cannot be indexed directly):
    #
    #   Huginn.configure { |c| c.search_strategy = :full_text;
    #                        c.fts_dictionary = "portuguese";
    #                        c.fts_function   = "public.f_tsvector" }
    #
    # Apply the same searchable model/association resolution as the trigram
    # generator, so both index sets cover identical columns.
    class FtsIndexesGenerator < Rails::Generators::Base
      include SearchableColumns

      source_root File.expand_path("templates", __dir__)

      argument :model_names, type: :array, default: [], desc: "Models to index (default: all Searchable models)"

      class_option :dictionary, type: :string, default: "portuguese",
                                desc: "tsvector dictionary pinned by the IMMUTABLE wrapper"

      def copy_migration
        @entries = resolve_entries
        @dictionary = options[:dictionary]
        return if @entries.empty?

        migration_template(
          "add_huginn_fts_indexes.rb.tt",
          "db/migrate/add_huginn_fts_indexes.rb"
        )
      end
    end
  end
end