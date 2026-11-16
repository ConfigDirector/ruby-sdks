# frozen_string_literal: true

require "configdirector"
require "json"
require "logger"
require "openssl"
require "socket"

class TlsStreamServer
  attr_reader :ends_of_a_stream_seen

  def initialize(certificate_path, key_path)
    tls_context = OpenSSL::SSL::SSLContext.new
    tls_context.cert = OpenSSL::X509::Certificate.new(File.read(certificate_path))
    tls_context.key = OpenSSL::PKey.read(File.read(key_path))
    @listener = TCPServer.new("127.0.0.1", 0)
    @tls_server = OpenSSL::SSL::SSLServer.new(@listener, tls_context)
    @streams = Queue.new
    @ends_of_a_stream_seen = Queue.new
    Thread.new { loop { serve(@tls_server.accept) } }
  end

  def url
    "https://127.0.0.1:#{@listener.addr[1]}"
  end

  def next_stream
    @streams.pop(timeout: 5)
  end

  def send_day(stream, day)
    event = "data: #{JSON.generate("kind" => "full", "configs" => { "day" => wire_config_serving(day) })}\n\n"
    stream.write("#{event.bytesize.to_s(16)}\r\n#{event}\r\n")
  end

  private

  def wire_config_serving(day)
    { "id" => "id-of-day", "key" => "day", "type" => "string", "target" => { "defaultValue" => day, "rules" => [] } }
  end

  def serve(connection)
    Thread.new do
      path = path_of_the_request_on(connection)
      next connection.write("HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n") unless path == "/server/sse/v1"

      connection.write("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nTransfer-Encoding: chunked\r\n\r\n")
      @streams << connection
      @ends_of_a_stream_seen << end_of_the_stream_on(connection)
    rescue IOError, SystemCallError, OpenSSL::SSL::SSLError
      nil
    end
  end

  def path_of_the_request_on(connection)
    path = connection.gets("\r\n").to_s.split[1]
    content_length = 0
    while (line = connection.gets("\r\n").to_s.chomp) != ""
      name, value = line.split(": ", 2)
      content_length = Integer(value, 10) if name.casecmp?("content-length")
    end
    connection.read(content_length)

    path
  end

  def end_of_the_stream_on(connection)
    connection.sysread(1)
    "bytes from the client"
  rescue EOFError
    "closed by the client"
  end
end

server = TlsStreamServer.new(*ARGV)
client = ConfigDirector.create_client(
  "server-sdk-key", connection: ConfigDirector::ConnectionOptions.new(url: server.url, timeout: 5),
                    logger: Logger.new(File::NULL)
)
forked = false
forked_process_ids = Queue.new
client.on(:configs_updated) do
  next if forked || client.get_value("day", "none") != "Tuesday"

  forked = true
  process_id = fork
  forked_process_ids << process_id unless process_id.nil?
end

initializing = Thread.new { client.init }
stream_of_the_parent = server.next_stream
server.send_day(stream_of_the_parent, "Monday")
initializing.join
server.send_day(stream_of_the_parent, "Tuesday")
_process_id, exit_status = Process.wait2(forked_process_ids.pop(timeout: 5))
sleep(0.5)
ends_seen = Array.new(server.ends_of_a_stream_seen.length) { server.ends_of_a_stream_seen.pop }
server.send_day(stream_of_the_parent, "Wednesday")
sleep(0.5)

puts JSON.generate(
  "exit_status_of_the_forked_process" => exit_status.exitstatus, "ends_of_a_stream_seen_by_the_server" => ends_seen,
  "day_served_by_the_parent" => client.get_value("day", "none")
)
$stdout.flush
exit!(0)
