# frozen_string_literal: true

require "rails/generators"
require "rails/generators/migration"

module Huginn
  module Generators
    # Shared logic between the index-scaffold generators
    # (huginn:trigram_indexes / huginn:fts_indexes): resolving the Searchable
    # models (or the explicit ones given as arguments) into the table/column
    # pairs that need an index, and the migration filename machinery.
    module SearchableColumns
      extend ActiveSupport::Concern

      included do
        include Rails::Generators::Migration

        # Rails::Generators::Migration leaves this as NotImplementedError; it
        # is expected to be overridden to produce the next migration number.
        def self.next_migration_number(dirname)
          number = current_migration_number(dirname) + 1
          ActiveRecord::Migration.next_migration_number(number)
        end
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