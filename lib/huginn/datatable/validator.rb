# frozen_string_literal: true

module Huginn
  module Datatable
    # Resolves and validates column references used by datatable filters,
    # orders and ranges.
    #
    # A field is either a plain column ("status"), an association-scoped
    # column ("pessoa.nome", "company.people.age") or — when the model
    # declares `huginn_attributes` — a *public* API alias that maps to the
    # real column.
    #
    # Fields are never interpolated into SQL strings: scoped fields are
    # resolved through `AssociationPath` (direction aware FK/PK linking) and
    # authorization is enforced against the `allowed_paths` allowlist. When
    # the model configures `huginn_attributes(strict: true)` only the
    # declared aliases are accepted, so the schema stays hidden from callers.
    class Validator
      FIELD_PATTERN = /\A[a-z_][a-z0-9_]*\z/

      def self.call(model, field)
        new(model, field)
      end

      def initialize(model, field)
        @model = model
        @public_name = field.to_s
        @strict_denied = false
        @field = resolve_alias(field)
        @field = @field.split(".").drop(1).join(".") if own_table_prefix?(@field)
      end

      def segments
        @segments ||= @field.split(".")
      end

      def plain?
        segments.size == 1
      end

      def scoped?
        !plain? && segments.size >= 2
      end

      def valid?
        return false if strict_denied?
        return false unless segments.all? { |segment| segment.match?(FIELD_PATTERN) }

        if plain?
          model.columns_hash.key?(column)
        else
          association_path&.valid? && association_path.target_klass.columns_hash.key?(column)
        end
      end

      # Canonical chain of association reflection names (e.g. ["company",
      # "people"]) used to match the allowlist. Table names and public aliases
      # are normalized through the reflection.
      def authorization_path
        return [] if plain?

        association_path&.association_names || []
      end

      def arel_attribute
        return nil unless valid?

        plain? ? model.arel_table[column] : association_path.target_table[column]
      end

      def column_type
        return nil unless valid?

        klass = plain? ? model : association_path.target_klass
        klass.columns_hash[column].type
      end

      # True for PostgreSQL array columns (e.g. `uuid[]`, `text[]`).
      def array?
        definition = column_definition
        !!(definition.respond_to?(:array?) ? definition.array? : definition&.try(:array))
      end

      # SQL type of the array elements ("uuid", "character varying"...),
      # used to cast the filter literal.
      def array_element_sql_type
        column_definition.sql_type.delete_suffix("[]")
      end

      # Casts a filter value with the array element type; nil when invalid.
      def cast_array_element(value)
        type = target_klass.type_for_attribute(column)
        element = type.respond_to?(:subtype) ? type.subtype : type
        element.serialize(element.cast(value))
      rescue ArgumentError, TypeError
        nil
      end

      # :any or :all, declared with huginn_attributes(array:) or
      # huginn_array_match (by public alias or by column name).
      def array_mode
        modes = target_klass.respond_to?(:huginn_array_modes) ? target_klass.huginn_array_modes : {}
        own = model.respond_to?(:huginn_array_modes) ? model.huginn_array_modes : {}
        own[@public_name] || own[@field] || modes[column] || :any
      end

      # The AssociationPath for scoped fields (builds filter/order
      # subqueries), or nil for plain columns.
      def association_path
        @association_path ||= (AssociationPath.call(model, @field) if scoped?)
      end

      # First association name of the chain (backwards compatible alias used
      # by specs), or nil for plain columns.
      def association_name
        return nil if plain?

        association_path&.association_names&.first&.to_sym
      end

      def correlated_order_expression
        association_path&.correlated_order_expression
      end

      def allowlist_key
        return nil if plain?

        joined = authorization_path.join(".")
        joined.empty? ? nil : joined
      end

      private

      attr_reader :model

      # "people.name" addressed via the model's own table_name is a plain
      # column of the base relation (model.table_name is, actually, "people"
      # for Person).
      def own_table_prefix?(field)
        segments = field.split(".")
        segments.size >= 2 && segments.first == model.table_name
      end

      def target_klass
        plain? ? model : association_path.target_klass
      end

      def column_definition
        return nil unless valid?

        target_klass.columns_hash[column]
      end

      def strict_denied?
        @strict_denied
      end

      def column
        segments.last
      end

      def resolve_alias(field)
        mapping = model.respond_to?(:huginn_attribute_mapping) ? model.huginn_attribute_mapping : nil
        return field.to_s if mapping.blank?

        key = field.to_s
        return mapping[key] if mapping.key?(key)

        @strict_denied = model.huginn_strict_mapping
        key
      end
    end
  end
end