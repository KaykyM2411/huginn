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

      it "orders by a scoped (associated) column when its path is allowed" do
        result = Person.datatable({ orders: [{ "company.name" => "desc" }] }, allowed_paths: [:company])
        expect(result[:data].first).to eq(@third)
      end

      it "uses a correlated scalar subquery for scoped ordering" do
        SqlSpy.start
        result = Person.datatable({ orders: [{ "company.name" => "desc" }] }, allowed_paths: [:company])
        result[:data].to_a
        SqlSpy.stop

        order_sql = SqlSpy.queries.find { |sql| sql.include?("ORDER BY (SELECT") }
        expect(order_sql).to be_present
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
      it "counts lean and preloads only the subset" do
        SqlSpy.start
        result = Company.datatable({ per_page: 2 }, allowed_paths: [:people], includes: [:products])
        result[:data].to_a # materializes the paginated subset, triggering the preload
        SqlSpy.stop

        count_query = SqlSpy.queries.find { |sql| sql.strip.start_with?("SELECT COUNT") }
        expect(count_query).to be_present
        expect(count_query).not_to include("DISTINCT")

        # Preload runs as a separate second query against the small subset,
        # not as a JOIN materialized in memory.
        expect(SqlSpy.queries.grep(/WHERE "products"\."company_id" IN/).size).to be >= 1
      end

      it "filters via a primary key subquery instead of a join" do
        SqlSpy.start
        Company.datatable({ filters: { "people.name" => "Kayky" } }, allowed_paths: [:people])
        SqlSpy.stop

        filter_sql = SqlSpy.queries.find { |sql| sql.include?('"id" IN (') }
        expect(filter_sql).to be_present
        expect(filter_sql).to include("companies")
        expect(filter_sql).to include("people")
        expect(filter_sql).to include("DISTINCT")
      end
    end

    describe "huginn_attributes aliases" do
      context "when the model declares a mapping (strict default)" do
        before do
          Person.huginn_attributes(
            name: "people.name",
            company_name: "companies.name",
            age: "people.age"
          )
        end

        after do
          Person.huginn_attribute_mapping = nil
          Person.huginn_strict_mapping = false
        end

        it "filters by a public alias even when the allowlist is empty" do
          result = Person.datatable({ filters: { "company_name" => "Acme Corp" } })
          expect(result[:total_count]).to eq(2)
        end

        it "orders by a public alias without an allowlist" do
          result = Person.datatable({ orders: [{ "company_name" => "desc" }] })
          expect(result[:data].first).to eq(@third)
        end

        it "maps a range_data alias" do
          result = Person.datatable({ range_data: { "age" => ["20", "29"] } })
          expect(result[:total_count]).to eq(1)
          expect(result[:data].first).to eq(@other)
        end

        it "rejects unknown fields while honoring mapped aliases" do
          result = Person.datatable({ filters: { "password" => "x", "name" => "Kayky" } })
          # "password" is not mapped (ignored), "name" is mapped and applied.
          expect(result[:total_count]).to eq(1)
          expect(result[:data].first).to eq(@person)
        end

        it "still works when the caller also passes the allowed path explicitly" do
          result = Person.datatable({ orders: [{ "company_name" => "asc" }] }, allowed_paths: [:company])
          expect(result[:total_count]).to eq(3)
        end
      end

      context "without a mapping (fallback)" do
        it "still accepts raw columns" do
          result = Person.datatable({ filters: { "name" => "Kayky" } })
          expect(result[:total_count]).to eq(1)
        end

        it "rejects scoped columns when no allowlist is given (strict deny-all)" do
          result = Person.datatable({ orders: [{ "company.name" => "desc" }] })
          expect(result[:data].first).to eq(@person)
        end
      end

      context "with a has_many alias (deduplicated by subquery)" do
        before do
          Company.huginn_attributes(name: "companies.name", people_name: "people.name")
          Person.create!(company: @acme, name: "Kayky", email: "dup@acme.com", age: 31)
        end

        after do
          Company.huginn_attribute_mapping = nil
          Company.huginn_strict_mapping = false
        end

        it "deduplicates rows through the pk IN subquery" do
          result = Company.datatable({ filters: { "people_name" => "Kayky" } })
          expect(result[:data].to_a.size).to eq(1)
          expect(result[:total_count]).to eq(1)
          expect(result[:data].first).to eq(@acme)
        end
      end
    end

    describe "allowed_paths allowlist" do
      it "enforces strict deny-all for scoped filters" do
        result = Person.datatable({ filters: { "company.name" => "Acme Corp" } })
        expect(result[:total_count]).to eq(3)
      end

      it "allows the scoped filter once the path is authorized" do
        result = Person.datatable(
          { filters: { "company.name" => "Acme Corp" } },
          allowed_paths: [:company]
        )
        expect(result[:total_count]).to eq(2)
      end

      it "accepts a Hash shape in the allowlist" do
        result = Person.datatable(
          { filters: { "company.name" => "Globex" } },
          allowed_paths: [{ company: [] }]
        )
        expect(result[:total_count]).to eq(1)
      end

      it "supports the table-name reference against the allowlist" do
        result = Person.datatable(
          { filters: { "companies.name" => "Acme Corp" } },
          allowed_paths: [:company]
        )
        expect(result[:total_count]).to eq(2)
      end

      it "applies a range on a scoped has_many column through a subquery" do
        Person.create!(company: @acme, name: "Marcelo2", email: "m2@acme.com", age: 27)
        result = Company.datatable(
          { range_data: { "people.age" => ["30", "30"] } },
          allowed_paths: [:people]
        )
        expect(result[:data].size).to eq(1)
        expect(result[:data].first).to eq(@acme)
      end

      it "orders by a has_many column using a correlated scalar subquery" do
        Person.create!(company: @acme, name: "Zed", email: "z@acme.com", age: 50)
        result = Company.datatable(
          { orders: [{ "people.name" => "asc" }] },
          allowed_paths: [:people]
        )
        expect(result[:data].first).to eq(@acme)
      end
    end
  end
end