# frozen_string_literal: true

module Huginn
  module Datatable
    extend ActiveSupport::Concern

    included do
      class_attribute :huginn_attribute_mapping, default: nil
      class_attribute :huginn_strict_mapping, default: false
    end

    class_methods do
      # Executes a datatable request in two phases:
      #
      #   phase 1  filtering & ordering built on join-subqueries and scalar
      #            correlated subqueries (never joins/loads data on the
      #            base relation)
      #   phase 2  lean count, pagination and preload of the small subset
      #
      # Association scoped fields are resolved as subqueries against the
      # primary key, so the base relation stays flat and the count is
      # lightweight. `allowed_paths` is a strict allowlist of the association
      # chains that may be filtered/ordered/ranged — anything else is
      # silently ignored.
      #
      # @param params [ActionController::Parameters, Hash] keys: :page,
      #   :per_page, :search, :filters, :range_data and :orders
      # @option allowed_paths [Array<Symbol, String, Hash>] strict allowlist of
      #   association chains for filtering/ordering/ranges (deny-all by default)
      # @option includes [Array<Symbol, Hash>] associations preloaded only on
      #   the final paginated subset (keeps queries lightweight)
      #
      # @return [Hash] { total_count: Integer, data: ActiveRecord::Relation }
      def datatable(params, allowed_paths: [], includes: [])
        relation = datatable_relation(params, allowed_paths: allowed_paths)
        Paginator.call(relation, params, includes: includes)
      end

      # Builds the filtered/ordered relation. Kept public so callers can
      # compose it with their own relation (e.g. tenant scoping) before
      # pagination.
      def datatable_relation(params, allowed_paths: [])
        allowlist = effective_allowed_paths(allowed_paths)
        relation = all

        relation = apply_datatable_search(relation, params[:search])
        relation = apply_datatable_filters(relation, params, allowlist)
        relation = apply_datatable_order(relation, params[:orders], allowlist)

        relation
      end

      # Declares the public API names that map to real columns (or
      # association-scoped columns), hiding the database schema.
      #
      #   huginn_attributes name: "users.name",
      #                     company_name: "companies.name"
      #
      # When `strict:` is true (default), fields not present in the mapping
      # are rejected — API callers can only filter/order by the aliases.
      # Without a mapping the model falls back to plain/reflected columns.
      # Accepts a positional Hash or keyword arguments.
      def huginn_attributes(mapping = nil, strict: true, **aliases)
        merged = (mapping || {}).merge(aliases)
        self.huginn_attribute_mapping = merged.map { |key, value| [key.to_s, value.to_s] }.to_h
        self.huginn_strict_mapping = strict
        huginn_attribute_mapping
      end

      private

      def apply_datatable_search(relation, value)
        return relation if value.blank? || !respond_to?(:search)

        relation.merge(search(value, distinct: false))
      end

      def apply_datatable_filters(relation, params, allowed)
        filters = FilterNormalizer.call(params[:filters])
        filters.each do |field, values|
          relation = apply_datatable_filter(relation, field, values, allowed)
        end

        each_range_data(params[:range_data]) do |field, value|
          relation = apply_datatable_range(relation, field, value, allowed)
        end

        relation
      end

      def apply_datatable_filter(relation, field, values, allowed)
        validator = Validator.call(self, field)
        return relation unless authorized_validator?(validator, allowed)

        if validator.plain?
          apply_plain_filter(relation, validator, Array(values))
        else
          apply_scoped_filter(relation, validator, Array(values))
        end
      end

      def apply_plain_filter(relation, validator, values)
        attr = validator.arel_attribute
        return relation if attr.nil?

        if values.include?("null")
          apply_nullable_predicate(relation, attr, values)
        elsif values.size == 1
          relation.where(attr.eq(values.first))
        else
          relation.where(attr.in(values))
        end
      end

      # Scoped filters run as: WHERE <base PK> IN (
      #   SELECT DISTINCT <base PK> FROM <chain> JOIN ... WHERE <target> IN ...)
      def apply_scoped_filter(relation, validator, values)
        subquery = association_ids_subquery(relation, validator)
        return relation unless subquery

        attr   = validator.arel_attribute
        target = if values.include?("null")
                   apply_nullable_predicate(subquery, attr, values)
                 elsif values.size == 1
                   subquery.where(attr.eq(values.first))
                 else
                   subquery.where(attr.in(values))
                 end

        relation.where(primary_key => target)
      end

      # A subquery over the same base relation (keeps tenant scoping) that
      # selects DISTINCT pk while joining the association chain of the field.
      def association_ids_subquery(relation, validator)
        chain = validator.authorization_path
        return nil if chain.empty?

        spec = AssociationPath.join_spec_for(chain.map(&:to_sym))
        base = relation.except(:select, :order, :offset, :limit)
                        .select(arel_table[primary_key])
                        .distinct
        base.joins(spec)
      end

      def apply_datatable_range(relation, field, value, allowed)
        values = Array(value)
        return relation if field.blank? || values.size < 2

        validator = Validator.call(self, field)
        return relation unless authorized_validator?(validator, allowed) && validator.valid?

        from, to = values[0], values[1]
        return relation if from.blank? && to.blank?

        if validator.plain?
          attr = validator.arel_attribute
          apply_range_predicate(relation, attr, from, to, validator.column_type)
        else
          apply_scoped_range(relation, validator, from, to)
        end
      end

      def apply_scoped_range(relation, validator, from, to)
        subquery = association_ids_subquery(relation, validator)
        return relation unless subquery

        attr = validator.arel_attribute
        target = apply_range_predicate(subquery, attr, from, to, validator.column_type)
        relation.where(primary_key => target)
      end

      def apply_range_predicate(relation, attr, from, to, type)
        if numeric_column?(type)
          from = to_numeric(from)
          to   = to_numeric(to)
          return relation if from.nil? && to.nil?

          predicate = range_predicate(attr, from, to)
          relation.where(predicate)
        else
          from = parse_datatable_date(from)
          to   = parse_datatable_date(to)
          return relation if from.blank? && to.blank?

          relation.where(range_predicate(attr, from, to))
        end
      end

      def range_predicate(attr, from, to)
        if from && to
          attr.between(from..to)
        elsif from
          attr.gteq(from)
        else
          attr.lteq(to)
        end
      end

      def numeric_column?(type)
        %i[integer decimal float].include?(type)
      end

      def to_numeric(value)
        value.to_f if value.present?
      rescue ArgumentError, TypeError
        nil
      end

      def apply_nullable_predicate(relation, attr, values)
        non_null = values.reject { |value| value == "null" }
        predicate = if non_null.empty?
                      attr.eq(nil)
                    elsif non_null.size == 1
                      attr.eq(non_null.first).or(attr.eq(nil))
                    else
                      attr.in(non_null).or(attr.eq(nil))
                    end
        relation.where(predicate)
      end

      def apply_datatable_order(relation, orders, allowed)
        return relation if orders.blank?

        Array(orders).compact.each do |item|
          next unless item.respond_to?(:each_pair)

          item.each_pair do |field, direction|
            validator = Validator.call(self, field)
            next unless authorized_validator?(validator, allowed)

            expression = if validator.plain?
                           validator.arel_attribute
                         else
                           validator.correlated_order_expression
                         end
            next if expression.nil?

            ordering = normalized_direction(direction) == "desc" ? expression.desc : expression.asc
            relation = relation.order(ordering)
          end
        end

        relation
      end

      def normalized_direction(direction)
        %w[asc desc].include?(direction.to_s.downcase) ? direction.to_s.downcase : "asc"
      end

      def authorized_validator?(validator, allowed)
        return false unless validator.valid?
        return true if validator.plain?

        chain = validator.authorization_path
        !chain.empty? && allowed.include?(chain)
      end

      # The allowlist, merged with the association chains reached by the
      # model's declared `huginn_attributes`, so declared aliases keep working
      # under strict authorization.
      def effective_allowed_paths(spec)
        allowed = AllowedPaths.call(self, spec)
        each_huginn_alias_path do |path|
          allowed.include_path(path)
        end
        allowed
      end

      def each_huginn_alias_path
        return unless respond_to?(:huginn_attribute_mapping) && huginn_attribute_mapping.present?

        huginn_attribute_mapping.each_value do |target|
          segments = target.to_s.split(".")
          yield segments[0..-2] if segments.size >= 2
        end
      end

      def each_range_data(range_data)
        return if range_data.blank?

        case range_data
        when ActionController::Parameters, Hash
          range_data.each_pair { |field, value| yield(field, value) }
        when Array
          range_data.each do |item|
            case item
            when ActionController::Parameters, Hash
              item.each_pair { |field, value| yield(field, value) }
            when Array
              field, value = item
              yield(field, value) if field
            end
          end
        end
      end

      def parse_datatable_date(value)
        return nil if value.blank?
        return value.to_date if value.respond_to?(:to_date)

        Date.parse(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end
    end
  end
end