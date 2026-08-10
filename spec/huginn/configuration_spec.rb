# frozen_string_literal: true

RSpec.describe Huginn::Configuration do
  subject(:config) { described_class.new }

  describe "defaults" do
    it "paginates with 10 items by default (up to 500)" do
      expect(config.pagy_items).to eq(10)
      expect(config.pagy_max_items).to eq(500)
    end

    it "defaults the unaccent function to the pg builtin" do
      expect(config.unaccent_function).to eq("unaccent")
    end

    it "defaults the FTS dictionary and function" do
      expect(config.fts_dictionary).to eq("portuguese")
      expect(config.fts_function).to eq("public.f_tsvector")
    end

    it "defaults the search strategy to :pg_trgm" do
      expect(config.search_strategy).to eq(:pg_trgm)
    end

    it "auto-includes the searchable and datatable concerns" do
      expect(config.auto_include_searchable?).to be(true)
      expect(config.auto_include_datatable?).to be(true)
    end
  end

  describe "#search_strategy" do
    it "normalizes a symbol to a symbol" do
      config.search_strategy = :full_text
      expect(config.search_strategy).to eq(:full_text)
    end

    it "normalizes a string to a symbol" do
      config.search_strategy = "pg_trgm"
      expect(config.search_strategy).to eq(:pg_trgm)
    end

    it "normalizes an array of strings to an array of symbols" do
      config.search_strategy = %w[pg_trgm full_text]
      expect(config.search_strategy).to eq(%i[pg_trgm full_text])
    end

    it "keeps an array of symbols with a single element as an array" do
      config.search_strategy = %i[full_text]
      expect(config.search_strategy).to eq(%i[full_text])
    end

    it "normalizes a single-element array of strings to an array of symbols" do
      config.search_strategy = ["full_text"]
      expect(config.search_strategy).to eq(%i[full_text])
    end
  end

  describe "#auto_include_* flags" do
    it "honors a false value for auto_include_searchable" do
      config.auto_include_searchable = false
      expect(config.auto_include_searchable?).to be(false)
    end

    it "honors a false value for auto_include_datatable" do
      config.auto_include_datatable = false
      expect(config.auto_include_datatable?).to be(false)
    end
  end
end