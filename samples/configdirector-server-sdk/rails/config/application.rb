# frozen_string_literal: true

require_relative "boot"

require "rails"
require "action_controller/railtie"

Bundler.require(*Rails.groups)

module RailsSample
  class Application < Rails::Application
    config.load_defaults 8.1
    config.api_only = true
    config.autoload_lib_once(ignore: [])
    config.log_level = ENV["CONFIGDIRECTOR_LOG_LEVEL"].presence || "info"
  end
end
