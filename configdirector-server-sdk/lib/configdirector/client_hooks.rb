# frozen_string_literal: true

module ConfigDirector
  # Handlers for the events a client emits, given to {ConfigDirector.create_client}. The client registers
  # them as {ConfigDirectorClient#on} would, in the order given and before any handler registered with
  # {ConfigDirectorClient#on}. Each event takes one handler or an Array of handlers, and a handler is any
  # object that responds to +call+, such as a lambda or +method(:name)+. An entry that does not respond to
  # +call+ is ignored and a warning is logged. Two hooks with the same handlers are equal.
  #
  # @example
  #   hooks = ConfigDirector::ClientHooks.new(
  #     client_ready: -> { puts "ConfigDirector is ready" },
  #     config_evaluated: ->(event) { puts "Evaluated #{event.evaluation.key}" }
  #   )
  #   client = ConfigDirector.create_client(ENV.fetch("CONFIGDIRECTOR_SERVER_KEY"), hooks: hooks)
  class ClientHooks
    include Internal::ComparedByValue

    # @return [#call, Array<#call>, nil] the +client_ready+ handlers, as given
    attr_reader :client_ready

    # @return [#call, Array<#call>, nil] the +configs_updated+ handlers, as given
    attr_reader :configs_updated

    # @return [#call, Array<#call>, nil] the +config_evaluated+ handlers, as given
    attr_reader :config_evaluated

    # @return [#call, Array<#call>, nil] the +connection_error+ handlers, as given
    attr_reader :connection_error

    # @param client_ready [#call, Array<#call>, nil] called with no argument once, when the client first
    #   receives values and becomes ready
    # @param configs_updated [#call, Array<#call>, nil] called with a {ConfigsUpdatedEvent} each time the
    #   client receives values, the first time included
    # @param config_evaluated [#call, Array<#call>, nil] called with a {ConfigEvaluatedEvent} each time a
    #   config is evaluated, before the read returns
    # @param connection_error [#call, Array<#call>, nil] called with a {ConnectionErrorEvent} when
    #   ConfigDirector refuses the connection and the client will not try again
    def initialize(client_ready: nil, configs_updated: nil, config_evaluated: nil, connection_error: nil)
      @client_ready = Internal::UnchangeableCopy.of(client_ready)
      @configs_updated = Internal::UnchangeableCopy.of(configs_updated)
      @config_evaluated = Internal::UnchangeableCopy.of(config_evaluated)
      @connection_error = Internal::UnchangeableCopy.of(connection_error)
      freeze
    end
  end
end
