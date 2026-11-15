# frozen_string_literal: true

module ConfigDirector
  # How a client connects to ConfigDirector. Connection options cannot be changed once built, and compare by
  # value.
  class ConnectionOptions
    include Internal::ComparedByValue

    # @return [String] the connection mode: +"streaming"+, +"polling"+ or +"offline"+
    attr_reader :mode

    # @return [Integer, Float] how often a polling client asks for new values, in seconds
    attr_reader :polling_interval

    # @return [Integer, Float] how long {ConfigDirectorClient#init} waits for the first values, in seconds. In
    #   polling mode it is also how long each request for values may take. It has no effect in offline mode.
    attr_reader :timeout

    # @return [String] the base URL of the ConfigDirector SDK server
    attr_reader :url

    # @return [String, Pathname, nil] the path of a JSON file holding the values an offline client serves
    attr_reader :file

    # @return [Hash, nil] the values an offline client serves, keyed by config key, as they were given
    attr_reader :values

    # @param mode [String] the connection mode. With +"streaming"+, the default, the connection stays open
    #   and receives a new value as soon as it changes in ConfigDirector. With +"polling"+, the client asks
    #   for new values every +polling_interval+. With +"offline"+, the client never connects to
    #   ConfigDirector, needs no server SDK key, and serves the values of +file+ or +values+ to every context,
    #   without applying targeting rules.
    # @param polling_interval [Integer, Float] how often a polling client asks for new values, in seconds. Defaults
    #   to 300 seconds. The minimum is 60 seconds: in polling mode a lower value is raised to 60 and a warning
    #   is logged.
    # @param timeout [Integer, Float] how long {ConfigDirectorClient#init} waits for the first values, in seconds.
    #   Defaults to 3 seconds. In polling mode it is also how long each request for values may take. It has no
    #   effect in offline mode.
    # @param url [String] the base URL of the ConfigDirector SDK server. Change it only to connect through
    #   a proxy.
    # @param file [String, Pathname, nil] the path of a JSON file holding the values to serve in offline mode,
    #   one value per config key, such as <tt>{"new-checkout": true, "max-items": 20}</tt>. A relative path is
    #   resolved against the working directory. {ConfigDirectorClient#init} reads the file each time it is
    #   called, and reads never read it. Only one of +file+ and +values+ can be given, and only in offline mode.
    # @param values [Hash, nil] the values to serve in offline mode, keyed by config key, such as
    #   <tt>{ "new-checkout": true, "max-items": 20 }</tt>. A key is a String or a Symbol, and a Symbol is read
    #   as its name. The config type of each value follows from its class: +true+ or +false+ is a boolean, an
    #   Integer an integer, a Float a float, a String a string, and a Hash or an Array a JSON config, which can
    #   hold +nil+. Only one of +file+ and +values+ can be given, and only in offline mode.
    def initialize(
      mode: "streaming",
      polling_interval: 300,
      timeout: 3,
      url: "https://server-sdk-api.configdirector.com",
      file: nil,
      values: nil
    )
      @mode = Internal::UnchangeableCopy.of(mode)
      @polling_interval = polling_interval
      @timeout = timeout
      @url = Internal::UnchangeableCopy.of(url)
      @file = Internal::UnchangeableCopy.of(file)
      @values = Internal::UnchangeableCopy.of(values)
      freeze
    end
  end
end
