# frozen_string_literal: true

require "spec_helper"

RSpec.describe "(integration) trigram GIN index usage" do
  before(:all) do
    require File.expand_path(
      "../../dummy/db/migrate/20240101000002_add_huginn_trigram_test_indexes.rb",
      __dir__
    )
    AddHuginnTrigramTestIndexes.migrate(:up)
    Huginn.configuration.unaccent_function = "public.f_unaccent"
    Person.class_eval { searchable_columns :name }
  end

  after(:all) do
    Huginn.configuration.unaccent_function = "unaccent"
    Person.class_eval { self.searchable_columns_config = nil }
    AddHuginnTrigramTestIndexes.migrate(:down) if ActiveRecord::Base.connection.table_exists?(:people)
  end

  it "still returns correct results with the index present" do
    company = Company.create!(name: "Acme")
    Person.create!(company: company, name: "Kayky Marcelo", email: "kayky@acme.com", age: 30)
    expect(Person.search("kayky").map(&:name)).to eq(["Kayky Marcelo"])
  end

  it "uses the GIN index (BitmapOr) when matching is forced to index paths" do
    connection = ActiveRecord::Base.connection
    connection.execute("SET enable_seqscan = off")
    begin
      plan = Person.search("kayky").explain.inspect
      expect(plan).to include("Bitmap Index Scan")
      expect(plan).to include("index_people_name_trgm")
    ensure
      connection.execute("SET enable_seqscan = on")
    end
  end
end