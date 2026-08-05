# frozen_string_literal: true

module Huginn
  class Configuration
    attr_accessor :fuzzy_threshold, :pagy_items, :pagy_max_items
    attr_writer :search_strategy, :auto_include_datatable, :auto_include_searchable

    def initialize
      @fuzzy_threshold = 0.3
      @pagy_items = 10
      @pagy_max_items = 500
      @search_strategy = :pg_trgm
      @auto_include_datatable = true
      @auto_include_searchable = true
    end

    # :pg_trgm  -> similarity(trgm) OR unaccent+ILIKE (recommended)
    # :unaccent -> unaccent + ILIKE only
    # :simple   -> plain LIKE
    def search_strategy
      @search_strategy.to_sym
    end

    def auto_include_datatable?
      @auto_include_datatable
    end

    def auto_include_searchable?
      @auto_include_searchable
    end
  end
end