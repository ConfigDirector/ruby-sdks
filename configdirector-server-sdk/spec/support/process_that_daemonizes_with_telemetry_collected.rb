# frozen_string_literal: true

require "configdirector"

client = ConfigDirector.create_client(
  "server-sdk-key", connection: ConfigDirector::ConnectionOptions.new(url: ARGV.fetch(0)),
                    logger: Logger.new(IO::NULL)
)
client.init
client.get_value("day-of-the-week", "read before Process.daemon")

Process.daemon(true, true)

client.get_value("day-of-the-week", "read after Process.daemon")
client.close
$stdout.write("closed")
