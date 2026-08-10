# frozen_string_literal: true

module Huginn
  class Configuration
    attr_accessor :pagy_items, :pagy_max_items, :unaccent_function,
                  :fts_dictionary, :fts_function
    attr_writer :search_strategy, :auto_include_datatable, :auto_include_searchable

    def initialize
      @pagy_items = 10
      @pagy_max_items = 500
      # The unaccent function SQL emits around searchable columns/terms. Defaults
      # to the pg builtin UNACCENT(). To let GIN trigram indexes be used, point
      # this at an IMMUTABLE wrapper (see `rails g huginn:trigram_indexes`),
      # e.g. "public.f_unaccent".
      @unaccent_function = "unaccent"
      # The tsvector wrapper and dictionary used by the :full_text strategy. The
      # wrapper (see `rails g huginn:fts_indexes`) pins the dictionary and is
      # IMMUTABLE so GIN tsvector indexes are usable.
      @fts_dictionary = "portuguese"
      @fts_function = "public.f_tsvector"
      @search_strategy = :pg_trgm
      @auto_include_datatable = true
      @auto_include_searchable = true
    end

    # :pg_trgm          -> trigram similarity (%) OR unaccent+ILIKE. The
    #                      similarity cutoff is the PostgreSQL GUC
    #                      pg_trgm.similarity_threshold (tune with
    #                      SELECT set_limit(...)); a gin_trgm_ops GIN index on
    #                      UNACCENT(col) is used when present.
    # :full_text        -> PostgreSQL full text search (lexemes): the column is
    #                      matched as to_tsvector(DICTIONARY, col) vs
    #                      plainto_tsquery(DICTIONARY, term). Needs the
    #                      fts_function wrapper and a GIN tsvector index.
    # :unaccent         -> unaccent + ILIKE only
    # :simple           -> plain LIKE
    #
    # Accepts a single symbol or an Array of symbols; when more than one is
    # given the generated predicates are combined with OR (a row matches if
    # any strategy matches).
    def search_strategy
      if @search_strategy.is_a?(Array)
        @search_strategy.map(&:to_sym)
      else
        @search_strategy.to_sym
      end
    end

    def auto_include_datatable?
      @auto_include_datatable
    end

    def auto_include_searchable?
      @auto_include_searchable
    end
  end
end