# frozen_string_literal: true

require "spec_helper"

RSpec.describe "(integration) Huginn::Searchable" do
  before do
    @acme = Company.create!(name: "Acme Corp")
    @globex = Company.create!(name: "Globex")
    Person.create!(company: @acme, name: "Kayky Marcelo", email: "kayky@acme.com", age: 30)
    Person.create!(company: @acme, name: "Ana Souza", email: "ana@acme.com", age: 25)
    Person.create!(company: @globex, name: "Avenida Ação", email: "outro@globex.com", age: 40)
  end

  describe ".search" do
    context "with default (all string/text) columns" do
      it "searches across name and email" do
        expect(Person.search("kayky").to_a).to contain_exactly(Person.find_by!(name: "Kayky Marcelo"))
      end

      it "is case-insensitive" do
        expect(Person.search("KAYKY").map(&:name)).to eq(["Kayky Marcelo"])
      end
    end

    context "overriding searchable columns" do
      it "honors an explicit declaration with an associated column" do
        Person.class_eval do
          include Huginn::Searchable
          searchable_columns :name, company: [:name]
        end
        expect(Person.search("globex").map(&:name)).to eq(["Avenida Ação"])
      ensure
        Person.class_eval { self.searchable_columns_config = nil }
      end

      it "does not fall back to own string columns when only associations are declared" do
        Person.class_eval { searchable_columns company: [:name] }

        expect(Person.search("kayky")).to be_empty
      ensure
        Person.class_eval { self.searchable_columns_config = nil }
      end
    end

    context "association-scoped search" do
      before do
        Person.class_eval { searchable_columns :name, company: [:name] }
      end

      after do
        Person.class_eval { self.searchable_columns_config = nil }
      end

      it "matches a company column through a pk subquery" do
        expect(Person.search("globex").map(&:name)).to eq(["Avenida Ação"])
      end

      it "does not duplicate rows when associations match many" do
        expect(Person.search("acme").map(&:name).size).to eq(2)
      end

      it "runs association matches as a semi-join subquery, never a join on the base relation" do
        SqlSpy.start
        Person.search("globex").to_a
        SqlSpy.stop

        query = SqlSpy.queries.find { |sql| sql.include?('"people"') && sql.include?("WHERE") }
        expect(query).to include('"people"."company_id" IN (SELECT DISTINCT "companies"."id"')
        expect(query).to match(/FROM "companies" WHERE/m)
        expect(query).not_to include('INNER JOIN "companies"')
        expect(query).not_to include("LEFT JOIN")
      end

      it "issues one pk subquery per distinct association chain, combined with OR" do
        @acme.products.create!(title: "Vonnegut", sku: "V-1")
        Person.class_eval { searchable_columns :name, "company.name", "company.products.title" }

        SqlSpy.start
        result = Person.search("vonnegut").to_a
        SqlSpy.stop

        query = SqlSpy.queries.find { |sql| sql.include?('"people"') && sql.include?("WHERE") }
        expect(result.map(&:name)).to contain_exactly("Ana Souza", "Kayky Marcelo")
        expect(query.scan(/"people"\."company_id" IN \(SELECT DISTINCT/).size).to eq(2)
        expect(query).to include('INNER JOIN "products"')
        expect(query).not_to include('INNER JOIN "companies"')
        expect(query).not_to include("LEFT JOIN")
      ensure
        Person.class_eval { self.searchable_columns_config = nil }
      end
    end

    context "association-scoped search on a has_many anchor" do
      before do
        Company.class_eval { searchable_columns :name, people: [:name] }
      end

      after do
        Company.class_eval { self.searchable_columns_config = nil }
      end

      it "matches a child column through an FK-anchored reverse subquery" do
        expect(Company.search("ana").map(&:name)).to eq(["Acme Corp"])
      end

      it "anchors the reverse subquery on the child FK, without re-scanning the base" do
        SqlSpy.start
        Company.search("avan").to_a
        SqlSpy.stop

        query = SqlSpy.queries.find { |sql| sql.include?('"companies"') && sql.include?("WHERE") }
        expect(query).to include('"companies"."id" IN (SELECT DISTINCT "people"."company_id"')
        expect(query).to match(/FROM "people" WHERE/m)
        expect(query).not_to include('INNER JOIN "people"')
        expect(query).not_to include("LEFT JOIN")
      ensure
        Company.class_eval { self.searchable_columns_config = nil }
      end
    end

    context "with :full_text strategy" do
      before do
        Person.class_eval { searchable_columns :name, company: [:name] }
      end

      after do
        Person.class_eval { self.searchable_columns_config = nil }
        Huginn.configuration.search_strategy = :pg_trgm
      end

      it "matches association columns through tsvector lexemes" do
        Huginn.configuration.search_strategy = :full_text
        expect(Person.search("globex").map(&:name)).to eq(["Avenida Ação"])
      end

      it "builds the FTS predicate inside the association subquery" do
        Huginn.configuration.search_strategy = :full_text

        SqlSpy.start
        Person.search("acme").to_a
        SqlSpy.stop

        query = SqlSpy.queries.find { |sql| sql.include?('"people"') && sql.include?("WHERE") }
        expect(query).to include('"people"."company_id" IN (SELECT DISTINCT "companies"."id"')
        expect(query).to include(
          'public.f_tsvector("companies"."name") @@ plainto_tsquery(\'portuguese\'::regconfig, \'acme\')'
        )
      end
    end

    context "combined :pg_trgm + :full_text strategies" do
      before do
        Person.class_eval { searchable_columns :name, company: [:name] }
        Huginn.configuration.search_strategy = [ :pg_trgm, :full_text ]
      end

      after do
        Person.class_eval { self.searchable_columns_config = nil }
        Huginn.configuration.search_strategy = :pg_trgm
      end

      it "combines both predicates with OR" do
        SqlSpy.start
        expectation = Person.search("globex").map(&:name)
        SqlSpy.stop

        query = SqlSpy.queries.find { |sql| sql.include?('"people"') && sql.include?("WHERE") }
        expect(expectation).to eq(["Avenida Ação"])
        expect(query).to include('%')
        expect(query).to include('@@ plainto_tsquery')
        expect(query).not_to include("LEFT JOIN")
      end
    end
  end
end