# frozen_string_literal: true

require "spec_helper"

RSpec.describe Huginn::Datatable::Paginator do
  let(:relation) { Person.all }

  let(:stub_pagy) do
    double("pagy", offset: 2, limit: 3, items: 3, count: 9)
  end

  before do
    allow_any_instance_of(described_class).to receive(:total_count).and_return(9)
  end

  def call(params)
    described_class.new(relation, params).call
  end

  context "when Pagy::Offset is available (Pagy >= 9.6 / 43.x)" do
    before do
      allow_any_instance_of(described_class).to receive(:offset_api?).and_return(true)
      expect(::Pagy::Offset).to receive(:new)
        .with(count: 9, page: 2, limit: 3)
        .and_return(stub_pagy)
    end

    it "builds pagination through Pagy::Offset and applies offset/limit" do
      result = call({ page: 2, per_page: 3 })
      expect(result[:total_count]).to eq(9)
      expect(result[:data].offset_value).to eq(2)
      expect(result[:data].limit_value).to eq(3)
    end
  end

  context "when Pagy.new still accepts the items: keyword (Pagy 6..8)" do
    before do
      allow_any_instance_of(described_class).to receive(:offset_api?).and_return(false)
      allow_any_instance_of(described_class).to receive(:items_keyword?).and_return(true)
      expect(::Pagy).to receive(:new)
        .with(count: 9, page: 2, items: 3)
        .and_return(stub_pagy)
    end

    it "builds pagination through the legacy items: interface" do
      result = call({ page: 2, per_page: 3 })
      expect(result[:data].offset_value).to eq(2)
      expect(result[:data].limit_value).to eq(3)
    end
  end

  describe "when Pagy.new speaks limit: instead of items: (Pagy 9.x legacy constructor)" do
    before do
      allow_any_instance_of(described_class).to receive(:offset_api?).and_return(false)
      allow_any_instance_of(described_class).to receive(:items_keyword?).and_return(false)
      expect(::Pagy).to receive(:new)
        .with(count: 9, page: 2, limit: 3)
        .and_return(stub_pagy)
    end

    it "builds pagination through the limit: interface" do
      result = call({ page: 2, per_page: 3 })
      expect(result[:data].offset_value).to eq(2)
      expect(result[:data].limit_value).to eq(3)
    end
  end
end