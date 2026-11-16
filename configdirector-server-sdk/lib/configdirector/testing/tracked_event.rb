# frozen_string_literal: true

module ConfigDirector
  module Testing
    TrackedEvent = Data.define(:name, :context, :value, :details)

    # An event the code under test tracked through the client of a {TestClient}, as {TestClient#tracked_events}
    # holds it. Two events with the same values are equal, so a test can compare the list with the events it expects.
    #
    # @example
    #   test_client.client.track("checkout-completed", ConfigDirector::Context.new(id: "user-123"), value: 49.9)
    #
    #   expect(test_client.tracked_events).to eq(
    #     [
    #       ConfigDirector::Testing::TrackedEvent.new(
    #         name: "checkout-completed", context: ConfigDirector::Context.new(id: "user-123"), value: 49.9
    #       )
    #     ]
    #   )
    #
    # @!attribute [r] name
    #   @return [String] the name the event was tracked with. A Symbol is held as its name.
    # @!attribute [r] context
    #   @return [Context, nil] the context the event was tracked for, or +nil+ when there was none or its kind was
    #     invalid
    # @!attribute [r] value
    #   @return [Integer, Float, nil] the value the event was tracked with, or +nil+ when there was none or it was
    #     not a finite number
    # @!attribute [r] details
    #   @return [Hash{String => Object}, nil] the details the event was tracked with, as the SDK sends them: keys
    #     and Symbols as their names, a Time as its ISO 8601 text in UTC, a Float that is not finite as +nil+, and a
    #     whole Float such as +50.0+ as the Integer +50+. +nil+ when there were none or the SDK leaves them out.
    class TrackedEvent
      # @param name [String] the name the event was tracked with
      # @param context [Context, nil] the context the event was tracked for
      # @param value [Integer, Float, nil] the value the event was tracked with
      # @param details [Hash{String => Object}, nil] the details, as the SDK sends them, with String keys
      def initialize(name:, context: nil, value: nil, details: nil)
        super(
          name: Internal::UnchangeableCopy.of(name), context: context, value: value,
          details: Internal::UnchangeableCopy.of(details)
        )
      end
    end
  end
end
