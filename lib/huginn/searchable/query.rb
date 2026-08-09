# frozen_string_literal: true

module Huginn
  module Searchable
    # Builds a tolerant full-text search relation over a model's searchable
    # columns, optionally crossing associations through left_joins.
    #
    # All matched columns are fused into a single Arel OR predicate, so the
    # whole search stays one query regardless of how many columns (or
    # associations) are involved.
    class Query
      def self.call(model, value, options = {})
        new(model, value, options).call
      end

      def initialize(model, value, options = {})
        @model = model
        @value = value.to_s
        @options = options
        @distinct = options.fetch(:distinct, true)
      end

      def call
        relation = @model.all
        return apply_distinct(relation) if @value.strip.empty?

        resolution = resolve_columns
        return apply_distinct(relation) if resolution.fetch(:attrs).empty?

        joins = resolution.fetch(:joins)
        relation = relation.left_joins(*joins) if joins.any?

        predicate = resolution.fetch(:attrs).map { |attr| fuzzy_predicate(attr) }.reduce(&:or)
        apply_distinct(relation.where(predicate))
      end

      private

      def resolve_columns
        columns = @model.searchable_columns_config_resolved
        joins = []
        attrs = []

        Array(columns[:columns]).map(&:to_s).reject(&:blank?).each do |field|
          if field.include?(".")
            name, col = field.split(".", 2)
            push_association(joins, attrs, name, col)
          else
            attrs << @model.arel_table[field] if @model.columns_hash.key?(field)
          end
        end

        columns[:associations].each do |name, cols|
          Array(cols).each { |col| push_association(joins, attrs, name.to_s, col.to_s) }
        end

        { joins: joins.uniq, attrs: attrs }
      end

      def push_association(joins, attrs, name, col)
        association = @model.reflect_on_association(name.to_sym)
        return unless association

        table = association.klass.arel_table
        attrs << table[col] if association.klass.columns_hash.key?(col)
        joins << name.to_sym unless joins.include?(name.to_sym)
      end

      def fuzzy_predicate(attr)
        case strategy
        when :pg_trgm
          if pg_trgm_available?
            Fuzzy::Trigram.new(attr, @value).predicate
          else
            fallback_fuzzy(attr)
          end
        when :unaccent
          Fuzzy::Unaccent.new(attr, @value).predicate
        else
          Fuzzy::Simple.new(attr, @value).predicate
        end
      end

      # Even with :pg_trgm configured, degrade gracefully to accent/case
      # insensitive matching when the extension is not installed.
      def fallback_fuzzy(attr)
        if unaccent_available?
          Fuzzy::Unaccent.new(attr, @value).predicate
        else
          Fuzzy::Simple.new(attr, @value).predicate
        end
      end

      def strategy
        Huginn.configuration.search_strategy
      end

      def pg_trgm_available?
        return false unless postgresql?
        @pg_trgm_available ||= extension_installed?("pg_trgm")
      end

      def unaccent_available?
        return false unless postgresql?
        @unaccent_available ||= extension_installed?("unaccent")
      end

      def extension_installed?(name)
        @model.connection
              .select_all(sanitize_extension_query(name))
              .any?
      end

      def sanitize_extension_query(name)
        ActiveRecord::Base.sanitize_sql_array(
          ["SELECT 1 AS one FROM pg_extension WHERE extname = ?", name]
        )
      end

      def postgresql?
        @model.connection.adapter_name.downcase.include?("postgres")
      end

      def apply_distinct(relation)
        @distinct ? relation.distinct : relation
      end
    end
  end
end