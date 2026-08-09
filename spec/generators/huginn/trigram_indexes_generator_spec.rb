# frozen_string_literal: true

require "spec_helper"
require "rails/generators"
require "generators/huginn/trigram_indexes/trigram_indexes_generator"

RSpec.describe Huginn::Generators::TrigramIndexesGenerator do
  let(:destination) { File.expand_path("../../dummy/tmp/generator", __dir__) }

  before do
    FileUtils.rm_rf(destination)
    FileUtils.mkdir_p(destination)
  end

  def rungenerator(*models)
    described_class.start(models, destination_root: destination)
  end

  def migration_path
    Dir.glob(File.join(destination, "db/migrate/*_add_huginn_trigram_indexes.rb")).first
  end

  it "generates a reversible GIN expression-index migration" do
    rungenerator("Person", "Product")

    path = migration_path
    expect(path).not_to be_nil
    migration = File.read(path)

    expect(migration).to include("class AddHuginnTrigramIndexes < ActiveRecord::Migration")
    expect(migration).to include('enable_extension "unaccent"')
    expect(migration).to include("CREATE OR REPLACE FUNCTION public.f_unaccent(text)")
    expect(migration).to include("IMMUTABLE")
    expect(migration).to include(
      'add_index :people, "public.f_unaccent(name) gin_trgm_ops", using: :gin, name: "index_people_name_trgm"'
    )
    expect(migration).to include(
      'add_index :people, "public.f_unaccent(email) gin_trgm_ops", using: :gin, name: "index_people_email_trgm"'
    )
    expect(migration).to include(
      'add_index :products, "public.f_unaccent(title) gin_trgm_ops", using: :gin, name: "index_products_title_trgm"'
    )
    expect(migration).to include("def up")
    expect(migration).to include("def down")
    expect(migration).to include('remove_index :people, name: "index_people_name_trgm"')
    expect(migration).to include("DROP FUNCTION IF EXISTS public.f_unaccent(text)")
  end

  it "includes association-scoped columns through their reflected table" do
    Person.class_eval { searchable_columns :name, company: [:name] }
    rungenerator("Person")

    migration = File.read(migration_path)
    expect(migration).to include(
      'add_index :companies, "public.f_unaccent(name) gin_trgm_ops", using: :gin, name: "index_companies_name_trgm"'
    )
  ensure
    Person.class_eval { self.searchable_columns_config = nil }
  end

  it "reports an unknown model without generating a migration" do
    expect { rungenerator("Nope") }.to output(/Could not find model/).to_stderr
    expect(Dir.glob(File.join(destination, "db/migrate/*.rb")).first).to be_nil
  end
end