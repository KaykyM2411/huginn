# frozen_string_literal: true

require "rails/generators"
require "rails/generators/migration"

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
      include Rails::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      argument :model_names, type: :array, default: [], desc: "Models to index (default: all Searchable models)"

      def self.next_migration_number(dirname)
        next_migration_number = current_migration_number(dirname) + 1
        ActiveRecord::Migration.next_migration_number(next_migration_number)
      end

      def copy_migration
        @entries = resolve_entries
        return if @entries.empty?

        migration_template(
          "add_huginn_trigram_indexes.rb.tt",
          "db/migrate/add_huginn_trigram_indexes.rb"
        )
      end

      private

      def resolve_entries
        models = if model_names.any?
                   model_names.map { |name| constantize(name) }
                 else
                   ActiveRecord::Base.descendants
                 end

        models.filter_map do |model|
          next unless model.respond_to?(:searchable_columns_config_resolved)

          columns_for(model)
        end.reject(&:empty?).flatten.uniq
      end

      def columns_for(model)
        scope = []
        resolved = model.searchable_columns_config_resolved

        Array(resolved[:columns]).map(&:to_s).reject(&:blank?).each do |field|
          scope << { table: model.table_name, column: field } if model.columns_hash.key?(field)
        end

        resolved[:associations].each do |assoc, cols|
          reflection = model.reflect_on_association(assoc.to_sym)
          next unless reflection

          Array(cols).map(&:to_s).each do |col|
            scope << { table: reflection.klass.table_name, column: col } if reflection.klass.columns_hash.key?(col)
          end
        end

        scope
      end

      def constantize(klass_name)
        klass_name.constantize
      rescue NameError
        raise Thor::Error, "Could not find model #{klass_name.inspect}"
      end
    end
  end
end