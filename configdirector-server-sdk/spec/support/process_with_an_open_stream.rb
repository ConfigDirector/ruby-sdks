# frozen_string_literal: true

require "configdirector"

first_event_delivered = Queue.new
transport = ConfigDirector::Internal::Streaming::StreamingTransport.new(
  endpoint: ConfigDirector::Internal::Streaming::StreamEndpoint.new(
    url: ARGV.fetch(0), server_sdk_key: "server-sdk-key", metadata: ConfigDirector::Metadata.new
  ),
  logger: Logger.new(IO::NULL)
)
transport.open(report_unrecoverable_error: ->(_error) {}) { |event_data| first_event_delivered << event_data }
first_event_delivered.pop
