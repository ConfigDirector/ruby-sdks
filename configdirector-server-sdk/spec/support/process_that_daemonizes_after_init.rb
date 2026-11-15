# frozen_string_literal: true

require "configdirector"
require_relative "waiting"

client = ConfigDirector.create_client(
  "server-sdk-key", connection: ConfigDirector::ConnectionOptions.new(url: ARGV.fetch(0)),
                    logger: Logger.new(IO::NULL)
)
client.init

Process.daemon(true, true)

Waiting.wait_up_to(5) { client.get_value("day-of-the-week", "Sunday") != "Monday" }
$stdout.write(client.get_value("day-of-the-week", "Sunday"))
