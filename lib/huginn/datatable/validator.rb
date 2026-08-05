# frozen_string_literal: true

module Huginn
  module Datatable
    # Resolves and validates column references used by datatable filters,
    # orders and ranges.
    #
    # A field is either a plain column ("status") or an association-scoped
    # column ("pessoa.nome"). Fields are never interpolated into SQL strings:
    # they are always mapped to an Arel attribute, or rejected.
    #
    # The `left_joins` produced by Rails alias the joined tables by the
    # association name, so Arel attributes are built against the association
    # klass table aliased with the association name rather than being guessed
    # from the field string (the historical `Arel::Table.new(t)` bug).
    class Validator
      FIELD_PATTERN = /\A[a-z_][a-z0-9_]*\z/

      def self.call(model, field)
        new(model, field)
      end

      def initialize(model, field)
        @model = model
        @field = field.to_s
      end

      def segments
        @field.split(".")
      end

      def valid?
        return false unless segments.size.between?(1, 2)
        return false unless segments.all? { |segment| segment.match?(FIELD_PATTERN) }

        exists?
      end

      # Returns an Arel::Attributes::Attribute for the field, or nil.
      def arel_attribute
        return nil unless valid?

        if scoped?
          association.klass.arel_table[column]
        else
          @model.arel_table[name.to_s]
        end
      end

      # Returns the ActiveRecord column type (:string, :integer, :date, ...).
      def column_type
        return nil unless valid?

        target.columns_hash[column].type
      end

      private

      def target
        scoped? ? association.klass : @model
      end

      def name
        segments.first
      end

      def column
        segments.last
      end

      def scoped?
        segments.size == 2
      end

      def exists?
        if scoped?
          association.present? && association.klass.columns_hash.key?(column)
        else
          @model.columns_hash.key?(name)
        end
      end

      def association
        @model.reflect_on_association(name.to_sym)
      end
    end
  end
end