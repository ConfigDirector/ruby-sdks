# frozen_string_literal: true

module ConfigDirector
  TelemetryOptions = Data.define(:event_queue_limit, :flush_interval)

  # Telemetry tuning. These settings rarely need to change. An application that evaluates a large number of
  # configs each second can use them to trade memory for how often telemetry is sent. Telemetry options
  # cannot be changed once built, compare by value, and +with+ builds a copy with other values.
  #
  # The client reports each {ConfigDirectorClient#get_value}, {ConfigDirectorClient#evaluate} and watch
  # delivery, and each context that has an +id+ and is not anonymous.
  #
  # @!attribute [r] event_queue_limit
  #   @return [Integer] how many telemetry events the client holds between two reports before it drops the
  #     oldest: evaluations up to 70% of it and contexts up to 30%
  # @!attribute [r] flush_interval
  #   @return [Integer, Float] how often the client sends its telemetry, in seconds
  class TelemetryOptions
    # @param event_queue_limit [Integer] how many telemetry events the client holds between two reports
    #   before it drops the oldest: evaluations up to 70% of it and contexts up to 30%. A number from 100 to
    #   100,000. Defaults to 5,000.
    # @param flush_interval [Integer, Float] how often the client sends its telemetry, in seconds. Defaults to 30
    #   seconds.
    def initialize(event_queue_limit: 5_000, flush_interval: 30)
      super
    end
  end
end
