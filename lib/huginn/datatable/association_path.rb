# frozen_string_literal: true

module Huginn
  module Datatable
    # Resolves a multi-segment association chain ("company.people.name") into
    # the concrete steps (tables, klasses and Arel link conditions) needed to
    # build:
    #
    #   * a subquery for filtering/ranges
    #     WHERE pk IN (SELECT DISTINCT pk FROM <chain> join ... WHERE ...)
    #
    #   * a correlated scalar subquery for ordering
    #     ORDER BY (SELECT col FROM <chain> join ... WHERE <correlation> ...)
    #
    # The link conditions are direction aware: a `belongs_to` puts the FK on
    # the owner table while `has_many`/`has_one` put it on the child table.
    # Association scopes are folded in as Arel predicates (never parsed SQL).
    class AssociationPath
      Step = Struct.new(:reflection, :klass, :table, :link_to_previous, keyword_init: true)

      attr_reader :segments, :column

      def self.call(model, field)
        new(model, field)
      end

      def initialize(model, field)
        @model = model
        @segments = field.to_s.split(".")
        @column = segments.last
      end

      # The association steps of the chain ("company", "people").
      def association_names
        resolved_steps.map { |step| step.reflection.name.to_s }
      end

      def target_klass
        resolved_steps.last.klass
      end

      def target_table
        resolved_steps.last.table
      end

      def valid?
        resolved_steps.present?
      end

      # The walkable Arel filter/order chain, or nil when invalid.
      def resolved_steps
        @steps ||= build_steps
      end

      # Correlated scalar subquery: ORDER BY (SELECT <col> FROM ... WHERE
      # <correlation> [AND scope...] ORDER BY <col> ASC LIMIT 1).
      # Deterministic: the smallest matching value per parent row.
      def correlated_order_expression
        steps = resolved_steps
        return nil unless steps

        manager = Arel::SelectManager.new
        manager.from(steps.first.table)
        steps.drop(1).each do |step|
          manager.join(step.table).on(step.link_to_previous)
        end

        # The first step correlates the subquery to the outer (base) table.
        manager.where(steps.first.link_to_previous)
        scope_predicates.each { |predicate| manager.where(predicate) }
        manager.project(target_table[column])
        manager.order(target_table[column].asc)
        manager.take(1)

        Arel.sql("(#{manager.to_sql})")
      rescue StandardError
        nil
      end

      # Reverse engineers a join spec usable by `ActiveRecord::Relation#joins`
      # for filter subqueries: `.joins(:people: { company: ... })`.
      def self.join_spec_for(names)
        names.reverse.reduce(nil) do |acc, name|
          acc.nil? ? name.to_sym : { name.to_sym => acc }
        end
      end

      private

      attr_reader :model

      def build_steps
        chain = @segments[0..-2]
        return nil if chain.empty?

        klass = model
        previous_table = model.arel_table
        walked = []

        chain.each do |name|
          reflection = klass.reflect_on_association(name.to_sym) || table_reflection(klass, name)
          return nil unless reflection

          decomposed_reflections(reflection).each do |ref|
            table = ref.klass.arel_table
            link  = join_link(ref, previous_table)
            return nil unless link

            walked << Step.new(reflection: ref, klass: ref.klass, table: table, link_to_previous: link)
            previous_table = table
            klass = ref.klass
          end
        end

        walked
      end

      # Flattens a through reflection into through + source reflections so the
      # chain walk stays uniform.
      def decomposed_reflections(reflection)
        if reflection.is_a?(ActiveRecord::Reflection::ThroughReflection)
          [reflection.through_reflection, reflection.source_reflection].compact
        else
          [reflection]
        end
      end

      # Allows a scoped column to be addressed by its table name instead of
      # the association name ("companies.name" vs "company.name"), matching
      # the base model's first reflection that resolves to that table.
      def table_reflection(klass, name)
        target = begin
          name.singularize.camelize.constantize
        rescue NameError
          nil
        end
        return nil unless target && target < ActiveRecord::Base

        klass.reflect_on_all_associations.find { |ref| ref.klass == target }
      end

      # Direction aware join condition:
      #   belongs_to ->   target_table[target_pk] = owner_table[fk]
      #   has_one/many -> child_table[fk]        = parent_table[parent_pk]
      def join_link(reflection, previous_table)
        current = reflection.klass.arel_table

        if reflection.belongs_to?
          current[reflection.join_primary_key].eq(previous_table[reflection.foreign_key])
        else
          current[reflection.foreign_key].eq(previous_table[reflection.active_record_primary_key])
        end
      end

      # Association scope (e.g. `has_many :people, -> { where(active: true) }`)
      # folded into the subquery through its Arel constraints instead of a
      # parsed WHERE string.
      def scope_predicates
        resolved_steps.flat_map do |step|
          next [] unless step.reflection.scope.is_a?(Proc)

          relation = step.klass.instance_exec(&step.reflection.scope)
          relation.instance_of?(ActiveRecord::Relation) ? relation.arel.constraints : []
        rescue StandardError
          []
        end
      end
    end
  end
end