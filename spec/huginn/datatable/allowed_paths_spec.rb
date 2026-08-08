# frozen_string_literal: true

require "spec_helper"

RSpec.describe Huginn::Datatable::AllowedPaths do
  describe ".call" do
    it "expands a Symbol to its canonical chain" do
      allowlist = described_class.call(Person, :company)
      expect(allowlist.to_a).to include(%w[company])
    end

    it "expands a nested Hash" do
      allowlist = described_class.call(Person, { company: :people }).to_a
      expect(allowlist).to include(%w[company])
      expect(allowlist).to include(%w[company people])
    end

    it "expands an Array mixing Symbols and Hashes" do
      allowlist = described_class.call(Company, [:name, { people: [] }]).to_a
      expect(allowlist).to include(%w[people])
    end

    it "treats an empty allowlist as deny-all" do
      expect(described_class.call(Person, [])).not_to be_any
    end

    it "canonicalizes a table-name segment to the reflection name" do
      allowlist = described_class.call(Person, "companies").to_a
      expect(allowlist).to include(%w[company])
    end
  end

  describe "#include?" do
    it "matches a canonical association chain" do
      allowlist = described_class.call(Person, :company)
      expect(allowlist.include?(%w[company])).to be(true)
    end

    it "rejects an unauthorized chain" do
      allowlist = described_class.call(Person, :company)
      expect(allowlist.include?(%w[people])).to be(false)
    end

    it "matches a table-name reference for a top-level allowed association" do
      allowlist = described_class.call(Person, :company)
      expect(allowlist.include?(%w[companies])).to be(true)
    end
  end

  describe "#include_path" do
    it "authorizes a chain produced by a huginn_attributes alias" do
      allowlist = described_class.call(Person, [])
      allowlist.include_path(%w[companies])
      expect(allowlist).to include(%w[company])
    end
  end
end