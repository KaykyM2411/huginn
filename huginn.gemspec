# frozen_string_literal: true

require_relative "lib/huginn/version"

Gem::Specification.new do |spec|
  spec.name          = "huginn"
  spec.version       = Huginn::VERSION
  spec.authors       = ["Kayky Marcelo"]
  spec.email         = ["kaykymarcelo2411@gmail.com"]

  spec.summary       = "Performant and elegant ActiveRecord datatables/data-grids with tolerant search"
  spec.description   = "Huginn is the raven of Odin that represents thought and remembrance. It offers a lightweight, highly performant query layer for ActiveRecord datatables: filtered/ordered eager-loaded pagination with an enxuto count and a PostgreSQL fuzzy-search builder (pg_trgm, unaccent, ILIKE)."
  spec.homepage      = "https://github.com/KaykyM2411/huginn"
  spec.license       = "MIT"

  spec.required_ruby_version = ">= 3.0"

  spec.files = Dir["lib/**/*", "README.md", "CHANGELOG.md", "LICENSE.txt", "logo.png"]
  spec.require_paths = ["lib"]

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/KaykyM2411/huginn"
  spec.metadata["changelog_uri"] = "https://github.com/KaykyM2411/huginn/blob/main/CHANGELOG.md"

  spec.add_dependency "activesupport", ">= 6.0"
  spec.add_dependency "activerecord", ">= 6.0"
  spec.add_dependency "actionpack", ">= 6.0"

  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "pry"
  spec.add_development_dependency "appraisal"
end