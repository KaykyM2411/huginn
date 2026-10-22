# frozen_string_literal: true

require "spec_helper"

RSpec.describe "(integration) Huginn::Datatable array filters" do
  let(:id_a) { "11111111-1111-4111-8111-111111111111" }
  let(:id_b) { "22222222-2222-4222-8222-222222222222" }

  before do
    @acme = Company.create!(name: "Acme Corp", labels: %w[cliente vip])
    @globex = Company.create!(name: "Globex", labels: %w[fornecedor])
    @ambos = Person.create!(company: @acme, name: "Ambos", tags: %w[a b], tag_ids: [id_a, id_b])
    @so_a = Person.create!(company: @acme, name: "Só A", tags: %w[a], tag_ids: [id_a])
    @so_b = Person.create!(company: @globex, name: "Só B", tags: %w[b], tag_ids: [id_b])
    @nenhum = Person.create!(company: @globex, name: "Nenhum", tags: [], tag_ids: [])
  end

  after do
    Person.huginn_attribute_mapping = nil
    Person.huginn_strict_mapping = false
    Person.huginn_array_modes = {}
  end

  def nomes(params = nil, allowed_paths: [], **filtros)
    Person.datatable(params || filtros, allowed_paths:)[:data].map(&:name).sort
  end

  it "matches rows that contain a single value" do
    expect(nomes(filters: { "tags" => "a" })).to eq(["Ambos", "Só A"])
  end

  it "matches any of several values by default, like IN" do
    expect(nomes(filters: [{ "tags" => "a" }, { "tags" => "b" }])).to eq(["Ambos", "Só A", "Só B"])
  end

  it "matches all values with huginn_array_match :all" do
    Person.huginn_array_match :tags, :all
    expect(nomes(filters: [{ "tags" => "a" }, { "tags" => "b" }])).to eq(["Ambos"])
  end

  it "matches empty arrays with null" do
    expect(nomes(filters: { "tags" => "null" })).to eq(["Nenhum"])
  end

  it "combines null with values" do
    expect(nomes(filters: [{ "tags" => "null" }, { "tags" => "b" }])).to eq(["Ambos", "Nenhum", "Só B"])
  end

  it "casts uuid values and drops invalid ones without hitting the database with them" do
    expect(nomes(filters: { "tag_ids" => id_b })).to eq(["Ambos", "Só B"])
    expect(nomes(filters: { "tag_ids" => "não-é-uuid" })).to eq([])
    expect(nomes(filters: [{ "tag_ids" => "x" }, { "tag_ids" => id_a }])).to eq(["Ambos", "Só A"])
  end

  it "accepts an alias with the array mode" do
    Person.huginn_attributes(etiquetas: { column: "people.tag_ids", array: :all }, name: "people.name")
    expect(nomes(filters: [{ "etiquetas" => id_a }, { "etiquetas" => id_b }])).to eq(["Ambos"])
    expect(nomes(filters: { "etiquetas" => id_a })).to eq(["Ambos", "Só A"])
  end

  it "filters an array column of an authorized association" do
    expect(nomes({ filters: { "company.labels" => "vip" } }, allowed_paths: [:company])).to eq(["Ambos", "Só A"])
    expect(nomes({ filters: { "company.labels" => "vip" } })).to eq(["Ambos", "Nenhum", "Só A", "Só B"])
  end

  it "keeps count and pagination consistent" do
    result = Person.datatable({ filters: [{ "tags" => "a" }, { "tags" => "b" }], page: 1, per_page: 2 })
    expect(result[:total_count]).to eq(3)
    expect(result[:data].to_a.size).to eq(2)
  end

  it "rejects an unknown array mode" do
    expect { Person.huginn_array_match :tags, :some }.to raise_error(ArgumentError)
  end

  it "still uses equality for plain columns" do
    expect(nomes(filters: { "name" => "Só A" })).to eq(["Só A"])
  end
end

RSpec.describe "(integration) Huginn::Searchable with array columns" do
  it "leaves array columns out of the default searchable columns" do
    Person.create!(company: Company.create!(name: "Acme"), name: "Kayky", tags: %w[kayky])
    expect(Person.send(:default_searchable_columns)).not_to include("tags")
    expect(Person.search("kayky").map(&:name)).to eq(["Kayky"])
  end
end
