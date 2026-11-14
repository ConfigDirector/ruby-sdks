# frozen_string_literal: true

module ConfigDirector
  # One handler registered with {ConfigDirectorClient#on} or one watch registered with
  # {ConfigDirectorClient#watch}, returned by the method that registered it.
  #
  # @example
  #   subscription = client.watch("new-checkout", false) { |enabled| puts enabled }
  #   subscription.close
  class Subscription
    # @api private
    def initialize(&removal)
      @removal = removal
      @closed = false
    end

    # Removes the handler or watch this subscription registered, and only that one, even when the same
    # handler or callback was registered again. It is safe to call more than once.
    #
    # @return [void]
    def close
      return if @closed

      @closed = true
      @removal.call
    end

    # @return [Boolean] whether {#close} has been called on this subscription. It stays +false+ when the
    #   handler or watch was removed another way, such as by {ConfigDirectorClient#close}.
    def closed?
      @closed
    end
  end
end
