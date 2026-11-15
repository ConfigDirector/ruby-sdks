# frozen_string_literal: true

require "json"
require "configdirector"

methods_of_process = %i[_fork fork daemon]
before_the_first_init = methods_of_process.to_h { |name| [name, Process.respond_to?(name)] }
client = ConfigDirector.create_client(
  connection: ConfigDirector::ConnectionOptions.new(mode: "offline"), logger: Logger.new(IO::NULL)
)
client.init
after_the_first_init = methods_of_process.to_h { |name| [name, Process.respond_to?(name)] }

$stdout.write(
  JSON.generate("before_the_first_init" => before_the_first_init, "after_the_first_init" => after_the_first_init)
)
