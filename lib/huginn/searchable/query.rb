# frozen_string_literal: true

require_relative "../datatable/association_path"

module Huginn
  module Searchable
    AssociationPath = Datatable::AssociationPath unless const_defined?(:AssociationPath)
    # Builds a tolerant full-text search relation over a model's searchable
    # columns. The matching predicate per column is driven by
    # Huginn.configuration.search_strategy (:pg_trgm, :full_text, :unaccent,
    # :simple — or an Array of them combined with OR).
    #
    # Columns are split in two groups following the datatable pattern:
    #
    #   * the model's own columns  -> direct fuzzy predicates on the base WHERE
    #   * association columns      -> reverse semi-join subqueries anchored on
    #                                  the first FK/has_many hop, so the base
    #                                  table is never re-scanned:
    #
    #        belongs_to ->  base[fk] IN (SELECT DISTINCT t1[pk]  FROM t1 ...)
    #        has_many   ->  base[pk]  IN (SELECT DISTINCT t1[fk] FROM t1 ...)
    #
    # Through/hand-joined chains keep the generic fallback:
    #        base[pk] IN (SELECT DISTINCT base[pk] FROM base JOIN <chain> ...)
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
        resolution.fetch(:associations).each do |_chain, group|
          predicate = association_predicate(group)
          predicates << predicate if predicate
        end

        return apply_distinct(relation) if predicates.empty?

        apply_distinct(relation.where(predicates.reduce(&:or)))
      end

      private

      def fuzzy_predicates(attrs)
        attrs.map { |attr| fuzzy_predicate(attr) }.compact
      end

      def resolve_columns
        columns = @model.searchable_columns_config_resolved
        own = []
        associations = Hash.new { |hash, key| hash[key] = { path: nil, attrs: [] } }

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

        group = groups[path.association_names]
        group[:path] ||= path
        group[:attrs] << path.target_table[path.column]
      end

      # Prefers the FK-anchored reverse semi-join; falls back to the generic
      # pk subquery for through chains or anything the reverse plan rejects.
      def association_predicate(group)
        path = group[:path]
        attrs = group[:attrs]
        return nil if path.nil? || attrs.empty?

        anchored_predicate(path, attrs)
      rescue StandardError
        generic_predicate(path, attrs)
      end

      # Reverse semi-join:
      #
      #   belongs_to -> base[fk]  IN (SELECT DISTINCT t1[join_pk]  FROM t1 ...)
      #   has_many   -> base[pk]   IN (SELECT DISTINCT t1[fk]      FROM t1 ...)
      #
      # Walks the chain from the first target table outwards so the base table
      # is never scanned inside the subquery.
      def anchored_predicate(path, attrs)
        if through_association?(path)
          return generic_predicate(path, attrs)
        end

        steps = path.resolved_steps
        first = steps.first
        reflection = first.reflection

        outer = if reflection.belongs_to?
                  arel_table[reflection.foreign_key]
                else
                  arel_table[reflection.active_record_primary_key]
                end

        projection = if reflection.belongs_to?
                       first.table[reflection.join_primary_key]
                     else
                       first.table[reflection.foreign_key]
                     end

        manager = Arel::SelectManager.new
        manager.from(first.table)
        steps.drop(1).each { |step| manager.join(step.table).on(step.link_to_previous) }
        manager.where(fuzzy_predicates(attrs).reduce(&:or))
        path.scope_constraints.each { |constraint| manager.where(constraint) }
        manager.project(projection)
        manager.distinct

        outer.in(manager)
      end

      # Whether the first hop goes through a join model; the FK anchoring is
      # ambiguous there so the generic pk subquery is used instead.
      def through_association?(path)
        reflection = @model.reflect_on_association(path.segments.first.to_sym)
        reflection.is_a?(ActiveRecord::Reflection::ThroughReflection)
      end

      # Generic fallback semi-join subquery over the base table, mirroring
      # datatable's association_ids_subquery:
      #   base[pk] IN (SELECT DISTINCT base[pk] FROM base JOIN <chain> ...).
      def generic_predicate(path, attrs)
        return nil unless path

        spec = AssociationPath.join_spec_for(path.association_names.map(&:to_sym))
        base = @model.all.except(:select, :order, :offset, :limit)
                        .select(arel_table[primary_key])
                        .distinct

        predicate = fuzzy_predicates(attrs).reduce(&:or)
        arel_table[primary_key].in(base.joins(spec).where(predicate).arel)
      end

      def fuzzy_predicate(attr)
        strategies = Array(strategy)
        predicates = strategies.map { |strat| predicate_for_strategy(attr, strat) }.compact
        return nil if predicates.empty?

        predicates.reduce(&:or)
      end

      def predicate_for_strategy(attr, strat)
        case strat
        when :pg_trgm
          if pg_trgm_available?
            Fuzzy::Trigram.new(attr, @value).predicate
          else
            fallback_fuzzy(attr)
          end
        when :full_text
          if fts_available?
            Fuzzy::FullText.new(attr, @value).predicate
          else
            fallback_fuzzy(attr)
          end
        when :unaccent
          Fuzzy::Unaccent.new(attr, @value).predicate
        when :simple
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

      # Whether the IMMUTABLE tsvector wrapper behind the :full_text strategy
      # exists (created by `rails g huginn:fts_indexes`). FTS is core
      # PostgreSQL, but without the wrapper the predicate would raise, so we
      # degrade to the unaccent fallback instead.
      def fts_available?
        return false unless postgresql?
        @fts_available ||= begin
          schema, name = split_function_name(Huginn.configuration.fts_function)
          @model.connection.select_value(
            ActiveRecord::Base.sanitize_sql_array(
              ["SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = ? AND p.proname = ?", schema, name]
            )
          ).present?
        end
      end

      def split_function_name(function)
        schema, _, name = function.to_s.rpartition(".")
        [schema.presence || "public", name]
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