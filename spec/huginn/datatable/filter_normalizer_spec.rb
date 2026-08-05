# frozen_string_literal: true

require "spec_helper"

RSpec.describe Huginn::Datatable::FilterNormalizer do
  subject(:normalizer) { described_class }

  context "with a Hash" do
    it "accumulates single values into arrays" do
      expect(normalizer.call({ "status" => "active" }))
        .to eq("status" => ["active"])
    end
  end

  context "with ActionController::Parameters" do
    it "converts through to_unsafe_h" do
      raw = ActionController::Parameters.new("status" => "active")
      expect(normalizer.call(raw)).to eq("status" => ["active"])
    end
  end

  context "with an Array of hashes" do
    it "accumulates duplicate keys into a single IN bucket" do
      raw = [{ "status" => "active" }, { "status" => "inactive" }].map do |h|
        ActionController::Parameters.new(h)
      end
      expect(normalizer.call(raw)).to eq("status" => %w[active inactive])
    end
  end

  context "with Array of [key, value] pairs" do
    it "merges them into one key" do
      raw = [["nome", "kayky"], ["nome", "outro"]]
      expect(normalizer.call(raw)).to eq("nome" => %w[kayky outro])
    end
  end

  context "with a single [key, value] pair (not a list)" do
    it "treats it as a pair" do
      expect(normalizer.call(["status", "active"]))
        .to eq("status" => ["active"])
    end
  end

  context "with an unrecognized payload" do
    it { expect(normalizer.call("nope")).to eq({}) }
    it { expect(normalizer.call(nil)).to eq({}) }
  end

  context "with symbol keys" do
    it "keeps them as strings" do
      expect(normalizer.call({ status: "active" })).to eq("status" => ["active"])
    end
  end
end