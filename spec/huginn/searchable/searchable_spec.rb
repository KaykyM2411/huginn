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
    end

    context "association-scoped search" do
      before do
        Person.class_eval { searchable_columns :name, company: [:name] }
      end

      after do
        Person.class_eval { self.searchable_columns_config = nil }
      end

      it "matches a company column through a left_join" do
        expect(Person.search("globex").map(&:name)).to eq(["Avenida Ação"])
      end

      it "does not duplicate rows when associations match many" do
        expect(Person.search("acme").map(&:name).size).to eq(2)
      end
    end
  end
end