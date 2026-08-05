# frozen_string_literal: true

module Huginn
  module Datatable
    extend ActiveSupport::Concern

    class_methods do
      # Executes a datatable request in two phases:
      #
      #   phase 1  filtering & ordering over left_joins (never loads data)
      #   phase 2  lean count, pagination and preload of the small subset
      #
      # @param params [ActionController::Parameters, Hash] keys: :page,
      #   :per_page, :search, :filters, :range_data and :orders
      # @option joins [Array<Symbol, Hash, String>] associations to left_join
      #   for filtering/ordering (never preloaded)
      # @option includes [Array<Symbol, Hash>] associations preloaded only on
      #   the final paginated subset (keeps queries lightweight)
      #
      # @return [Hash] { total_count: Integer, data: ActiveRecord::Relation }
      def datatable(params, joins: [], includes: [])
        relation = datatable_relation(params, joins: joins)
        Paginator.call(relation, params, includes: includes)
      end

      # Builds the filtered/ordered relation. Kept public so callers can
      # compose it with their own relation (e.g. tenant scoping) before
      # pagination.
      def datatable_relation(params, joins: [])
        relation = all
        joins = Array(joins).compact

        relation = relation.left_joins(*joins) if joins.any?
        relation = apply_datatable_search(relation, params[:search])
        relation = apply_datatable_filters(relation, params)
        relation = apply_datatable_order(relation, params[:orders])
        relation = relation.distinct if distinct_needed_relation(relation)

        relation
      end

      private

      def apply_datatable_search(relation, value)
        return relation if value.blank? || !respond_to?(:search)

        relation.merge(search(value, distinct: false))
      end

      def apply_datatable_filters(relation, params)
        filters = FilterNormalizer.call(params[:filters])
        filters.each do |field, values|
          relation = apply_datatable_filter(relation, field, values)
        end

        each_range_data(params[:range_data]) do |field, value|
          relation = apply_datatable_range(relation, field, value)
        end

        relation
      end

      def apply_datatable_filter(relation, field, values)
        validator = Validator.call(self, field)
        return relation unless validator.valid?

        attr = validator.arel_attribute
        return relation if attr.nil?

        values = Array(values)
        if values.include?("null")
          non_null = values.reject { |value| value == "null" }
          predicate = if non_null.empty?
                        attr.eq(nil)
                      elsif non_null.size == 1
                        attr.eq(non_null.first).or(attr.eq(nil))
                      else
                        attr.in(non_null).or(attr.eq(nil))
                      end
          relation.where(predicate)
        elsif values.size == 1
          relation.where(attr.eq(values.first))
        else
          relation.where(attr.in(values))
        end
      end

      def apply_datatable_range(relation, field, value)
        values = Array(value)
        return relation if field.blank? || values.size < 2

        validator = Validator.call(self, field)
        return relation unless validator.valid?

        attr = validator.arel_attribute
        return relation if attr.nil?

        from, to = values[0], values[1]
        return relation if from.blank? && to.blank?

        if numeric_column?(validator.column_type)
          apply_numeric_range(relation, attr, from, to)
        else
          apply_date_range(relation, attr, from, to)
        end
      end

      def apply_numeric_range(relation, attr, from, to)
        from = to_numeric(from)
        to = to_numeric(to)
        return relation if from.nil? && to.nil?

        predicate = if from && to then attr.between(from..to)
                    elsif from then attr.gteq(from)
                    else attr.lteq(to) end
        relation.where(predicate)
      end

      def apply_date_range(relation, attr, from, to)
        from = parse_datatable_date(from)
        to = parse_datatable_date(to)
        return relation if from.blank? && to.blank?

        predicate = if from && to then attr.between(from..to)
                    elsif from then attr.gteq(from)
                    else attr.lteq(to) end
        relation.where(predicate)
      end

      def numeric_column?(type)
        %i[integer decimal float].include?(type)
      end

      def to_numeric(value)
        value.to_f if value.present?
      rescue ArgumentError, TypeError
        nil
      end

      def apply_datatable_order(relation, orders)
        return relation if orders.blank?

        Array(orders).compact.each do |item|
          next unless item.respond_to?(:each_pair)

          item.each_pair do |field, direction|
            validator = Validator.call(self, field)
            next unless validator.valid?

            attr = validator.arel_attribute
            next if attr.nil?

            relation = relation.order(normalize_direction(direction) == "desc" ? attr.desc : attr.asc)
          end
        end

        relation
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

      def normalize_direction(direction)
        %w[asc desc].include?(direction.to_s.downcase) ? direction.to_s.downcase : "asc"
      end

      # `left_joins` populates +left_outer_joins_values+ (not +joins_values+).
      # DISTINCT is only applied when a joined association multiplies rows
      # (has_many / HABTM): single-valued joins (belongs_to / has_one) never
      # duplicate rows, so we avoid DISTINCT there. Otherwise PG rejects
      # `SELECT DISTINCT ... ORDER BY <joined.column>`.
      def distinct_needed_relation(relation)
        (relation.left_outer_joins_values + relation.joins_values).any? do |name|
          multiplying_join?(name)
        end
      end

      def multiplying_join?(value)
        case value
        when Symbol, String
          reflection = reflect_on_association(value.to_sym)
          reflection ? reflection.collection? : false
        when Hash
          value.any? { |key, nested| multiplying_join?(key) || nested.is_a?(Hash) && multiplying_join?(nested) }
        else
          false
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