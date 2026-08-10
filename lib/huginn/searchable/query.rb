# frozen_string_literal: true

require_relative "../datatable/association_path"

module Huginn
  module Searchable
    AssociationPath = Datatable::AssociationPath unless const_defined?(:AssociationPath)
    # Builds a tolerant full-text search relation over a model's searchable
    # columns.
    #
    # Columns are split in two groups following the datatable pattern:
    #
    #   * the model's own columns  -> direct fuzzy predicates on the base WHERE
    #   * association columns      -> semi-join subqueries on the primary key
    #                                  pk IN (SELECT DISTINCT pk FROM base
    #                                       JOIN <chain> ... WHERE <fuzzy>)
    #
    # The base relation never carries joins, so every match group stays one
    # query and the count remains a plain COUNT(*). Multiple association
    # chains produce one subquery each, combined with OR.
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
        predicates = fuzzy_predicates(resolution.fetch(:own))
        resolution.fetch(:associations).each do |chain, attrs|
          subquery = association_subquery(chain, attrs)
          predicates << arel_table[primary_key].in(subquery.arel) if subquery
        end

        return apply_distinct(relation) if predicates.empty?

        apply_distinct(relation.where(predicates.reduce(&:or)))
      end

      private

      def fuzzy_predicates(attrs)
        attrs.map { |attr| fuzzy_predicate(attr) }
      end

      def resolve_columns
        columns = @model.searchable_columns_config_resolved
        own = []
        associations = Hash.new { |hash, key| hash[key] = [] }

        Array(columns[:columns]).map(&:to_s).reject(&:blank?).each do |field|
          if field.include?(".")
            chain, column = field.split(".", 2)
            push_association(associations, chain, column)
          else
            own << @model.arel_table[field] if @model.columns_hash.key?(field)
          end
        end

        columns[:associations].each do |name, cols|
          Array(cols).each { |column| push_association(associations, name.to_s, column.to_s) }
        end

        { own: own, associations: associations }
      end

      def push_association(groups, chain, column)
        path = AssociationPath.call(@model, "#{chain}.#{column}")
        return unless path.valid?
        return unless path.target_klass.columns_hash.key?(path.column)

        groups[path.association_names] << path.target_table[path.column]
      end

      # Semi-join subquery over the base table: DISTINCT pk while joining the
      # association chain of the group and applying the fuzzy predicates on the
      # target columns. Mirrors datatable's association_ids_subquery.
      def association_subquery(chain, attrs)
        return nil if chain.empty?

        spec = AssociationPath.join_spec_for(chain.map(&:to_sym))
        base = @model.all.except(:select, :order, :offset, :limit)
                        .select(arel_table[primary_key])
                        .distinct

        predicate = fuzzy_predicates(attrs).reduce(&:or)
        base.joins(spec).where(predicate)
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

      def arel_table
        @model.arel_table
      end

      def primary_key
        @model.primary_key
      end

      def apply_distinct(relation)
        @distinct ? relation.distinct : relation
      end
    end
  end
end