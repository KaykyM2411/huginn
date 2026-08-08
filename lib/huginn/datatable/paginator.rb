# frozen_string_literal: true

require "pagy"

module Huginn
  module Datatable
    # Splits datatable execution into two phases:
    #
    #   1. build the filtered/ordered relation
    #   2. count lean, paginate with Pagy, then preload associations only
    #      on the small paginated subset.
    #
    # The count runs against a stripped relation (no select/includes/order/
    # offset/limit) selecting only the primary key with DISTINCT, so that
    # PostgreSQL answers it through the PK index as a subquery instead of a
    # massive COUNT(DISTINCT ...) over the joins.
    class Paginator
      attr_reader :relation, :params, :includes

      def self.call(relation, params, includes: [])
        new(relation, params, includes: includes).call
      end

      def initialize(relation, params, includes: [])
        @relation = relation
        @params = params
        @includes = Array(includes).compact
      end

      def call
        pagy = build_pagy
        data = relation.offset(pagy.offset).limit(limit_for(pagy))
        data = data.preload(*includes) if includes.any?

        { total_count: pagy.count, data: data }
      end

      private

      def build_pagy
        page = params.fetch(:page, 1).to_i
        items = params.fetch(:per_page, nil).presence || config.pagy_items
        items = items.to_i
        items = config.pagy_max_items if items > config.pagy_max_items
        items = 1 if items < 1
        page = 1 if page < 1

        if offset_api?
          ::Pagy::Offset.new(count: total_count, page: page, limit: items)
        elsif items_keyword?
          ::Pagy.new(count: total_count, page: page, items: items)
        else
          ::Pagy.new(count: total_count, page: page, limit: items)
        end
      end

      # Pagy >= 9.6 replaced the `Pagy#new` items/first API with the dedicated
      # `Pagy::Offset` class that speaks `limit:`. Older releases (6..9.4) live
      # under the legacy `Pagy.new(count:page:items:)` interface.
      def offset_api?
        defined?(::Pagy::Offset)
      end

      # Pagy 10.0 renamed the page-size keyword from `items:` to `limit:` while
      # keeping `Pagy.new`. Probe the constructor instead of guessing by
      # version number.
      def items_keyword?
        ::Pagy.instance_method(:initialize).parameters.any? do |type, name|
          type == :key && name == :items
        end
      end

      def limit_for(pagy)
        pagy.respond_to?(:limit) ? pagy.limit : pagy.items
      end

      def total_count
        stripped = relation.except(:select, :includes, :order, :offset, :limit)
        return stripped.count unless stripped.left_outer_joins_values.any? || stripped.joins_values.any?

        stripped.select(stripped.arel_table[stripped.primary_key]).distinct.count
      end

      def config
        Huginn.configuration
      end
    end
  end
end