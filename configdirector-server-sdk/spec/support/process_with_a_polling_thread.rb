# frozen_string_literal: true

require "configdirector"

transport = ConfigDirector::Internal::Polling::PollingTransport.new(
  endpoint: ConfigDirector::Internal::Polling::PollingEndpoint.new(
    url: ARGV.fetch(0), server_sdk_key: "server-sdk-key", metadata: ConfigDirector::Metadata.new
  ),
  timing: ConfigDirector::Internal::Polling::PollTiming.on_the_clock_of_the_process(
    seconds_between_polls: 60, seconds_a_poll_may_take: 30
  ),
  logger: Logger.new(IO::NULL)
)
transport.open(report_unrecoverable_error: ->(_error) {}) { |_payload_text| nil }
