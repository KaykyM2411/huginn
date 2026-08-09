# frozen_string_literal: true

module Huginn
  class Configuration
    attr_accessor :pagy_items, :pagy_max_items, :unaccent_function
    attr_writer :search_strategy, :auto_include_datatable, :auto_include_searchable

    def initialize
      @pagy_items = 10
      @pagy_max_items = 500
      # The unaccent function SQL emits around searchable columns/terms. Defaults
      # to the pg builtin UNACCENT(). To let GIN trigram indexes be used, point
      # this at an IMMUTABLE wrapper (see `rails g huginn:trigram_indexes`),
      # e.g. "public.f_unaccent".
      @unaccent_function = "unaccent"
      @search_strategy = :pg_trgm
      @auto_include_datatable = true
      @auto_include_searchable = true
    end

    # :pg_trgm  -> trigram similarity (%) OR unaccent+ILIKE. The similarity
    #              cutoff is the PostgreSQL GUC pg_trgm.similarity_threshold
    #              (tune with SELECT set_limit(...)); a gin_trgm_ops GIN index
    #              on UNACCENT(col) is used when present.
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