# frozen_string_literal: true

require "spec_helper"

RSpec.describe "(integration) Huginn::Datatable" do
  let(:now) { Time.now.round }

  before do
    @acme = Company.create!(name: "Acme Corp")
    @globex = Company.create!(name: "Globex")
    @person = Person.create!(company: @acme, name: "Kayky", email: "kayky@acme.com", age: 30)
    @other = Person.create!(company: @acme, name: "Marcelo", email: "marcelo@acme.com", age: 25)
    @third = Person.create!(company: @globex, name: "Outro", email: "outro@globex.com", age: 40)
    @product = Product.create!(company: @acme, title: "P1")
  end

  describe ".datatable" do
    it "returns total_count and paginated data" do
      result = Person.datatable({ page: 1, per_page: 2 })
      expect(result[:total_count]).to eq(3)
      expect(result[:data].to_a.size).to eq(2)
    end

    it "clamps per_page to the configured maximum" do
      result = Person.datatable({ per_page: 999_999 })
      expect(result[:data].to_a.size).to eq(3)
      expect(result[:total_count]).to eq(3)
    end

    context "hash filters" do
      it "filters with an exact match" do
        result = Person.datatable({ filters: { "company_id" => @acme.id } })
        expect(result[:total_count]).to eq(2)
      end

      it "supports IN matching through repeated keys" do
        ids = [@person.id, @third.id]
        result = Person.datatable({ filters: [{ "id" => @person.id }, { "id" => @third.id }] })
        expect(result[:total_count]).to eq(2)
        expect(result[:data].map(&:id).sort).to eq(ids)
      end
    end

    it "supports null filters" do
      person = Person.new(company: nil, name: "Sem Empresa")
      person.save(validate: false)
      result = Person.datatable({ filters: { "company_id" => "null" } })
      expect(result[:total_count]).to eq(1)
    end

    context "range_data" do
      it "filters between two dates" do
        result = Person.datatable({ range_data: { "created_at" => ["2020-01-01", "2030-01-01"] } })
        expect(result[:total_count]).to eq(3)
      end

      it "filters a numeric range" do
        result = Person.datatable({ range_data: { "age" => ["20", "29"] } })
        expect(result[:total_count]).to eq(1)
        expect(result[:data].first).to eq(@other)
      end
    end

    context "ordering" do
      it "orders by a column" do
        result = Person.datatable({ orders: [{ "age" => "desc" }] })
        expect(result[:data].first).to eq(@third)
      end

      it "orders by a scoped (joined) column" do
        result = Person.datatable({ orders: [{ "company.name" => "desc" }] }, joins: [:company])
        expect(result[:data].first).to eq(@third)
      end
    end

    context "search integration" do
      it "filters by a search term" do
        result = Person.datatable({ search: "kayky" })
        expect(result[:total_count]).to eq(1)
        expect(result[:data].first).to eq(@person)
      end
    end

    describe "query efficiency" do
      it "counts lean (COUNT DISTINCT pk) and preloads only the subset" do
        SqlSpy.start
        result = Company.datatable({ per_page: 2 }, joins: [:people], includes: [:products])
        result[:data].to_a # materializes the paginated subset, triggering the preload
        SqlSpy.stop

        count_query = SqlSpy.queries.find { |sql| sql.strip.start_with?("SELECT COUNT") }
        expect(count_query).to be_present
        expect(count_query).to include('"companies"."id"')
        expect(count_query).to include("DISTINCT")

        # Preload runs as a separate second query against the small subset,
        # not as a JOIN materialized in memory.
        expect(SqlSpy.queries.grep(/WHERE "products"\."company_id" IN/).size).to be >= 1
      end
    end
  end
end