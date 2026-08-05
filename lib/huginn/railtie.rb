# frozen_string_literal: true

module Huginn
  class Railtie < Rails::Railtie
    initializer "huginn.configure" do |app|
      ActiveSupport.on_load(:active_record) do
        include Huginn::Datatable if Huginn.configuration.auto_include_datatable?
        include Huginn::Searchable if Huginn.configuration.auto_include_searchable?
      end
    end
  end
end