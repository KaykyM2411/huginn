# frozen_string_literal: true

require "active_support"
require "active_support/concern"
require "active_support/notifications"
require "active_record"

require "logger"

module Huginn
  NAMESPACE = "huginn"

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    def instrument(event, payload = {})
      ActiveSupport::Notifications.instrument("#{event}.#{NAMESPACE}", payload) do
        yield if block_given?
      end
    end

    def logger
      @logger ||= if defined?(Rails) && Rails.respond_to?(:logger)
                    Rails.logger
                  else
                    ::Logger.new($stdout)
                  end
    end
  end
end

require_relative "huginn/version"
require_relative "huginn/configuration"
require_relative "huginn/datatable"
require_relative "huginn/searchable"
require_relative "huginn/railtie" if defined?(Rails::Railtie)