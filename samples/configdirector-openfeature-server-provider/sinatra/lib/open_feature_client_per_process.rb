# frozen_string_literal: true

require "logger"

module OpenFeatureClientPerProcess
  @lock = Mutex.new
  @client = nil

  def self.client
    @lock.synchronize { @client ||= client_after_registering_the_provider }
  end

  def self.client_after_registering_the_provider
    logger = Logger.new($stdout, level: value_set_in_the_environment("CONFIGDIRECTOR_LOG_LEVEL") || "info")
    register(configdirector_provider_the_environment_names(logger), logger)
    at_exit { OpenFeature::SDK.shutdown }
    client = OpenFeature::SDK.build_client
    logger.info("Registered the ConfigDirector provider of process #{Process.pid}. Status: #{client.provider_status}")
    client
  end

  def self.configdirector_provider_the_environment_names(logger)
    ConfigDirector::OpenFeature::ConfigDirectorProvider.new(
      value_set_in_the_environment("CONFIGDIRECTOR_SERVER_KEY") || "fake-sample-key",
      metadata: ConfigDirector::Metadata.new(app_name: "openfeature-sinatra-sample", app_version: "1.0.0"),
      connection: connection_options_the_environment_names,
      logger: logger
    )
  end

  def self.register(provider, logger)
    OpenFeature::SDK.set_provider_and_wait(provider)
  rescue OpenFeature::SDK::ProviderInitializationError => e
    logger.warn(e.message)
  end

  def self.connection_options_the_environment_names
    named_options = {
      mode: value_set_in_the_environment("CONFIGDIRECTOR_MODE"),
      timeout: value_set_in_the_environment("CONFIGDIRECTOR_TIMEOUT")&.then { |seconds| Float(seconds) },
      url: value_set_in_the_environment("CONFIGDIRECTOR_BASE_URL")
    }
    ConfigDirector::ConnectionOptions.new(**named_options.compact)
  end

  def self.value_set_in_the_environment(name)
    value = ENV.fetch(name, "")
    value unless value.empty?
  end

  private_class_method :client_after_registering_the_provider, :configdirector_provider_the_environment_names,
                       :register, :connection_options_the_environment_names, :value_set_in_the_environment
end
