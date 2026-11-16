# frozen_string_literal: true

module ConfigDirector
  # Telemetry tuning. These settings rarely need to change. An application that evaluates a large number of
  # configs each second can use them to trade memory for how often telemetry is sent. Telemetry options
  # cannot be changed once built, and compare by value.
  #
  # The client reports each {ConfigDirectorClient#get_value}, {ConfigDirectorClient#evaluate} and watch
  # delivery, and each context that has an +id+ and is not anonymous.
  class TelemetryOptions
    include Internal::ComparedByValue

    # @return [Integer] how many telemetry events the client holds between two reports before it drops the
    #   oldest: evaluations up to 70% of it and contexts up to 30%
    attr_reader :event_queue_limit

    # @return [Integer, Float] how often the client sends its telemetry, in seconds
    attr_reader :flush_interval

    # @param event_queue_limit [Integer] how many telemetry events the client holds between two reports
    #   before it drops the oldest: evaluations up to 70% of it and contexts up to 30%. A number from 100 to
    #   100,000. Defaults to 5,000.
    # @param flush_interval [Integer, Float] how often the client sends its telemetry, in seconds. Defaults to 30
    #   seconds.
    def initialize(event_queue_limit: 5_000, flush_interval: 30)
      @event_queue_limit = event_queue_limit
      @flush_interval = flush_interval
      freeze
    end
  end
end
