# frozen_string_literal: true

require "spec_helper"

RSpec.describe Huginn::Datatable::Validator do
  subject(:validator) { described_class.call(Person, field) }

  let(:field) { "name" }

  def render_sql(node)
    ActiveRecord::Base.connection.visitor.compile(node)
  end

  describe "#valid?" do
    context "with a plain existing column" do
      it { expect(validator).to be_valid }
    end

    context "with a scoped existing column" do
      let(:field) { "company.name" }
      it { expect(validator).to be_valid }
    end

    context "with a scoped table-name column" do
      let(:field) { "companies.name" }
      it { expect(validator).to be_valid }
    end

    context "with an unknown column" do
      let(:field) { "nope" }
      it { expect(validator).not_to be_valid }
    end

    context "with an unknown association" do
      let(:field) { "missing.name" }
      it { expect(validator).not_to be_valid }
    end

    context "with an invalid column on a valid association" do
      let(:field) { "company.nope" }
      it { expect(validator).not_to be_valid }
    end

    context "with three segments" do
      let(:field) { "company.people.name" }
      it { expect(validator).to be_valid }
    end

    context "with an unsafe field" do
      let(:field) { %{company.name); DROP TABLE people; --} }
      it { expect(validator).not_to be_valid }
    end
  end

  describe "#arel_attribute" do
    it "resolves the base table for a plain column" do
      expect(render_sql(validator.arel_attribute)).to eq('"people"."name"')
    end

    context "when scoped to an association" do
      let(:field) { "company.name" }

      it "resolves the candidate by its real (reflected) table name" do
        sql = render_sql(validator.arel_attribute)
        expect(sql).to include('"companies"')
        expect(sql).to include('"name"')
      end
    end

    context "when scoped to a table name" do
      let(:field) { "companies.name" }

      it "resolves through the constantized model" do
        sql = render_sql(validator.arel_attribute)
        expect(sql).to include('"companies"')
        expect(sql).to include('"name"')
      end
    end
  end

  describe "huginn_attributes aliases" do
    after do
      Person.huginn_attribute_mapping = nil
      Person.huginn_strict_mapping = false
    end

    context "with a mapping configured (strict default)" do
      before do
        Person.huginn_attributes(
          name: "people.name",
          company_name: "companies.name"
        )
      end

      it "resolves a public alias to its mapped column" do
        validator = described_class.call(Person, "company_name")
        expect(validator).to be_valid
        expect(render_sql(validator.arel_attribute)).to include('"companies"')
        expect(validator.association_name).to eq(:company)
      end

      it "resolves a plain mapped alias" do
        validator = described_class.call(Person, "name")
        expect(validator).to be_valid
        expect(render_sql(validator.arel_attribute)).to eq('"people"."name"')
      end

      it "rejects unknown fields in strict mode" do
        expect(described_class.call(Person, "email")).not_to be_valid
        expect(described_class.call(Person, "password_hash")).not_to be_valid
      end
    end

    context "with a mapping targeting an association name" do
      before do
        Person.huginn_attributes(company_name: "company.name")
      end

      it "resolves and exposes the association for joining" do
        validator = described_class.call(Person, "company_name")
        expect(validator).to be_valid
        expect(validator.association_name).to eq(:company)
      end
    end

    context "with strict: false" do
      before do
        Person.huginn_attributes({ name: "people.name" }, strict: false)
      end

      it "still maps declared aliases" do
        expect(described_class.call(Person, "name")).to be_valid
      end

      it "accepts real columns as fallback" do
        expect(described_class.call(Person, "email")).to be_valid
      end
    end
  end
end