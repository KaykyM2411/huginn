# frozen_string_literal: true

require "spec_helper"

RSpec.describe Huginn::Searchable::Fuzzy do
  let(:column) { Person.arel_table[:name] }

  describe Huginn::Searchable::Fuzzy::Trigram do
    subject { described_class.new(column, "kayky").predicate.to_sql }

    it "uses the indexable % operator on UNACCENT columns" do
      expect(subject).to include('unaccent("people"."name") % unaccent(\'kayky\')')
    end

    it "keeps the unaccent+ILIKE substring fallback" do
      expect(subject).to include('unaccent("people"."name") ILIKE unaccent(\'%kayky%\')')
    end

    it "does not rely on the non-indexable similarity() function" do
      expect(subject).not_to include("similarity")
    end
  end

  describe Huginn::Searchable::Fuzzy::Unaccent do
    it "wraps both sides in UNACCENT with ILIKE" do
      sql = described_class.new(column, "café").predicate.to_sql
      expect(sql).to include('unaccent("people"."name") ILIKE unaccent(\'%café%\')')
    end

    it "escapes LIKE wildcards" do
      sql = described_class.new(column, "100%").predicate.to_sql
      expect(sql).to include('unaccent(\'%100\\%%\')')
    end
  end

  describe Huginn::Searchable::Fuzzy::Simple do
    it "uses plain LIKE with escaped wildcards" do
      sql = described_class.new(column, "100%").predicate.to_sql
      expect(sql).to include('LIKE \'%100\\%%\'')
    end
  end
end