require "active_support"
require "active_record"
require "action_controller"
require "rails"
require "huginn"

ENV["RAILS_ENV"] = "test"

require File.expand_path("dummy/config/application.rb", __dir__)
Dummy::Application.initialize!

require "rspec/rails"

ActiveRecord::Schema.verbose = false

module SqlSpy
  @queries = []
  @subscriber = nil

  class << self
    attr_reader :queries

    def start
      @queries = []
      @subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
        payload = args.last
        next if payload[:name] == "SCHEMA"
        @queries << payload[:sql]
      end
    end

    def stop
      ActiveSupport::Notifications.unsubscribe(@subscriber) if @subscriber
      @subscriber = nil
    end

    def reset
      stop
      @queries = []
    end
  end
end

RSpec.configure do |config|
  config.use_transactional_fixtures = true

  config.before(:suite) do
    require File.expand_path("dummy/db/migrate/20240101000001_create_huginn_test_tables.rb", __dir__)
    begin
      CreateHuginnTestTables.migrate(:up)
    rescue ActiveRecord::StatementInvalid
      # tables already exist; continue
    end

    # Removes data left behind by previous raw runs so per-example fixtures
    # (seeded inside the wrapping transaction) are not inflated.
    ActiveRecord::Base.connection.tables.each do |table|
      next if table == "schema_migrations" || table == "ar_internal_metadata"
      ActiveRecord::Base.connection.exec_query("TRUNCATE TABLE #{table} RESTART IDENTITY CASCADE")
    end
  end

  config.after(:suite) do
    ActiveRecord::Base.connection_pool.disconnect! if ActiveRecord::Base.connected?
  end

  config.around(:each) do |example|
    SqlSpy.reset
    example.run
    SqlSpy.reset
  end
end