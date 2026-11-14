# frozen_string_literal: true

module ConfigDirectorClientPerProcess
  @lock = Mutex.new
  @client = nil

  def self.client
    @lock.synchronize { @client ||= created_and_initialized_client }
  end

  def self.created_and_initialized_client
    client = ConfigDirector.create_client(
      ENV["CONFIGDIRECTOR_SERVER_KEY"].presence || "fake-sample-key",
      metadata: ConfigDirector::Metadata.new(app_name: "rails-sample", app_version: "1.0.0"),
      connection: connection_options_the_environment_names,
      logger: Rails.logger
    )
    client.init
    Rails.logger.info("Created the ConfigDirector client of process #{Process.pid}. Ready: #{client.ready?}")
    at_exit { client.close }
    client
  end

  def self.connection_options_the_environment_names
    named_options = {
      mode: ENV["CONFIGDIRECTOR_MODE"].presence,
      timeout: ENV["CONFIGDIRECTOR_TIMEOUT"].presence&.then { |seconds| Float(seconds) },
      url: ENV["CONFIGDIRECTOR_BASE_URL"].presence
    }
    ConfigDirector::ConnectionOptions.new(**named_options.compact)
  end

  private_class_method :created_and_initialized_client, :connection_options_the_environment_names
end
