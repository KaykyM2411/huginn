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
    # The base relation never carries joins (association filters, ranges,
    # orders and the search are all resolved through primary-key subqueries),
    # so the count stays a plain COUNT(*) over the stripped relation.
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

      # Pagy >= 43 exposes the dedicated `Pagy::Offset` class that speaks
      # `limit:`. Releases 6..9 carry the legacy `Pagy.new(count:page:items:)`
      # interface instead.
      def offset_api?
        defined?(::Pagy::Offset)
      end

      # Pagy 6..8 accept the page size through the `items:` constructor key and
      # expose it through `#items`. Pagy 9 restructured the constructors, but
      # the early 9.x releases keep `Pagy.new` keyed on `limit:`. Probe the
      # live constructor instead of guessing by version number.
      def items_keyword?
        sample = ::Pagy.new(count: 100, page: 1, items: 7)
        sample.respond_to?(:items) && sample.items == 7
      rescue StandardError
        false
      end

      def limit_for(pagy)
        pagy.respond_to?(:limit) ? pagy.limit : pagy.items
      end

      def total_count
        relation.except(:select, :includes, :order, :offset, :limit).count
      end

      def config
        Huginn.configuration
      end
    end
  end
end