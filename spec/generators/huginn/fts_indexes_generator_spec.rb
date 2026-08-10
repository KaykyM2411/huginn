# frozen_string_literal: true

require "spec_helper"
require "rails/generators"
require "generators/huginn/fts_indexes/fts_indexes_generator"

RSpec.describe Huginn::Generators::FtsIndexesGenerator do
  let(:destination) { File.expand_path("../../dummy/tmp/generator", __dir__) }

  before do
    FileUtils.rm_rf(destination)
    FileUtils.mkdir_p(destination)
  end

  def rungenerator(*models, **options)
    args = models.dup
    options.each { |key, value| args.concat([ "--#{key}", value.to_s ]) }
    described_class.start(args, destination_root: destination)
  end

  def migration_path
    Dir.glob(File.join(destination, "db/migrate/*_add_huginn_fts_indexes.rb")).first
  end

  it "generates a reversible GIN tsvector-expression migration" do
    rungenerator("Person", "Product")

    path = migration_path
    expect(path).not_to be_nil
    migration = File.read(path)

    expect(migration).to include("class AddHuginnFtsIndexes < ActiveRecord::Migration")
    expect(migration).to include("CREATE OR REPLACE FUNCTION public.f_tsvector(text)")
    expect(migration).to include("IMMUTABLE")
    expect(migration).to include("SELECT to_tsvector('portuguese', $1)")
    expect(migration).to include(
      'add_index :people, "public.f_tsvector(name)", using: :gin, name: "index_people_name_fts"'
    )
    expect(migration).to include(
      'add_index :people, "public.f_tsvector(email)", using: :gin, name: "index_people_email_fts"'
    )
    expect(migration).to include(
      'add_index :products, "public.f_tsvector(title)", using: :gin, name: "index_products_title_fts"'
    )
    expect(migration).to include("def up")
    expect(migration).to include("def down")
    expect(migration).to include('remove_index :people, name: "index_people_name_fts"')
    expect(migration).to include("DROP FUNCTION IF EXISTS public.f_tsvector(text)")
  end

  it "honors the --dictionary option" do
    rungenerator("Person", dictionary: "english")

    migration = File.read(migration_path)
    expect(migration).to include("SELECT to_tsvector('english', $1)")
  end

  it "includes association-scoped columns through their reflected table" do
    Person.class_eval { searchable_columns :name, company: [:name] }
    rungenerator("Person")

    migration = File.read(migration_path)
    expect(migration).to include(
      'add_index :companies, "public.f_tsvector(name)", using: :gin, name: "index_companies_name_fts"'
    )
  ensure
    Person.class_eval { self.searchable_columns_config = nil }
  end

  it "reports an unknown model without generating a migration" do
    expect { rungenerator("Nope") }.to output(/Could not find model/).to_stderr
    expect(Dir.glob(File.join(destination, "db/migrate/*.rb")).first).to be_nil
  end
end