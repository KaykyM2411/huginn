require "rails"
require "active_record/railtie"
require "action_controller/railtie"

module Dummy
  class Application < Rails::Application
    config.root = File.expand_path("..", __dir__)
    config.load_defaults Rails::VERSION::STRING.to_f
    config.eager_load = false
    config.secret_key_base = "huginn_dummy_secret_key_base"
  end
end