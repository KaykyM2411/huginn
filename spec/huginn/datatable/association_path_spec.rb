# frozen_string_literal: true

require "spec_helper"

RSpec.describe Huginn::Datatable::AssociationPath do
  subject(:path) { described_class.call(model, field) }

  let(:model) { Person }

  def render(sql)
    ActiveRecord::Base.connection.visitor.compile(sql)
  end

  describe "#valid?" do
    context "with a belongs_to chain" do
      let(:field) { "company.name" }
      it { expect(path).to be_valid }
    end

    context "with a has_many chain" do
      let(:model) { Company }
      let(:field) { "people.name" }
      it { expect(path).to be_valid }
    end

    context "with a deep ancestor chain" do
      let(:field) { "company.people.name" }
      it { expect(path).to be_valid }
    end

    context "with an unknown association" do
      let(:field) { "missing.name" }
      it { expect(path).not_to be_valid }
    end
  end

  describe "#association_names" do
    it "returns the reflection names of the chain" do
      expect(described_class.call(Person, "company.people.name").association_names)
        .to eq(%w[company people])
    end

    it "matches the table name to the reflection" do
      expect(described_class.call(Person, "companies.name").association_names)
        .to eq(%w[company])
    end
  end

  describe "correlated scalar order subquery (direction aware)" do
    it "links a belongs_to chain through the owner's FK (target.pk = owner.fk)" do
      sql = render(described_class.call(Person, "company.name").correlated_order_expression)
      expect(sql).to include('"companies"."id" = "people"."company_id"')
    end

    it "links a has_many chain through the child FK (child.fk = parent.pk)" do
      sql = render(described_class.call(Company, "people.name").correlated_order_expression)
      expect(sql).to include('"people"."company_id" = "companies"."id"')
    end

    it "is deterministic (ORDER BY column ASC LIMIT 1)" do
      sql = render(described_class.call(Person, "company.name").correlated_order_expression)
      expect(sql).to include('ORDER BY "companies"."name" ASC LIMIT 1')
    end
  end

  describe ".join_spec_for" do
    it "builds a nested hash for deepest-first chains" do
      expect(described_class.join_spec_for(%w[company people])).to eq({ company: :people })
    end
  end
end