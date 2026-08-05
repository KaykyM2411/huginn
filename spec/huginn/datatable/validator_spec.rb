# frozen_string_literal: true

require "spec_helper"

RSpec.describe Huginn::Datatable::Validator do
  subject(:validator) { described_class.call(Person, field) }

  let(:field) { "name" }

  describe "#valid?" do
    context "with a plain existing column" do
      it { expect(validator).to be_valid }
    end

    context "with a scoped existing column" do
      let(:field) { "company.name" }
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
      it { expect(validator).not_to be_valid }
    end

    context "with an unsafe field" do
      let(:field) { %{company.name); DROP TABLE people; --} }
      it { expect(validator).not_to be_valid }
    end
  end

describe "#arel_attribute" do
    def render_sql(node)
      ActiveRecord::Base.connection.visitor.compile(node)
    end

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
  end
end