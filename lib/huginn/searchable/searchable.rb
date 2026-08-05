# frozen_string_literal: true

module Huginn
  module Searchable
    extend ActiveSupport::Concern

    included do
      class_attribute :searchable_columns_config, default: nil
    end

    class_methods do
      # Declares which columns (own or association-scoped) are searched.
      #
      #   searchable_columns :name, :document
      #   searchable_columns :name, person: [:name, :email]
      #   searchable_columns "person.name"
      #
      # When nothing is declared, every :string/:text column of the model is
      # searched automatically. Columns may be association-scoped ("person.name")
      # or declared via keyword arguments; scoped columns are reached through a
      # left_join.
      def searchable_columns(*columns, **associations)
        self.searchable_columns_config = {
          columns: columns.flatten.compact.map(&:to_s),
          associations: associations
        }
        searchable_columns_config
      end

      # Tolerant full-text search (pg_trgm / unaccent / LIKE chain).
      #
      # @param value [String] the raw search term from the frontend
      # @param options [Hash] :distinct (default true), :columns override
      def search(value, options = {})
        Searchable::Query.call(self, value, options)
      end

      def searchable_columns_config_resolved
        config = searchable_columns_config || {}
        {
          columns: config[:columns].presence || default_searchable_columns,
          associations: config[:associations] || {}
        }
      end

      private

      def default_searchable_columns
        columns_hash.each_with_object([]) do |(name, column), acc|
          acc << name if %i[string text].include?(column.type)
        end
      end
    end
  end
end