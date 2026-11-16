# frozen_string_literal: true

require "json"
require "socket"

class ScriptedSdkServer
  STREAM_PATH = "/server/sse/v1"
  HEARTBEAT_PATH = "/server/heartbeat/v1"
  POLLING_PATH = "/server/polling/v1"
  TELEMETRY_PATH = "/server/telemetry/v1"
  LEVELS_OF_JSON_THE_SDK_SERVER_READS = 128

  class HeldRequest
    attr_reader :path, :headers, :body

    def initialize(socket, path, headers, body)
      @socket = socket
      @path = path
      @headers = headers
      @body = body
    end

    def json
      JSON.parse(body, max_nesting: LEVELS_OF_JSON_THE_SDK_SERVER_READS)
    end

    def answer(status:, headers: {}, body: "")
      write_answer_head(status, headers.merge("Content-Length" => body.bytesize.to_s))
      @socket.write(body)
      @socket.close
    end

    def answer_with_a_body_that_never_arrives(status:, content_length:)
      write_answer_head(status, "Content-Length" => content_length.to_s)
    end

    def answer_in_pieces(status:, pieces:, seconds_between_pieces: 0, &after_each_piece)
      write_answer_head(status, "Content-Length" => pieces.sum(&:bytesize).to_s)
      pieces.each do |piece|
        @socket.write(piece)
        after_each_piece&.call
        sleep(seconds_between_pieces)
      end
      @socket.close
      :sent_whole
    rescue IOError, SystemCallError
      :cut_off_by_the_client
    end

    def answer_with_a_body_cut_off(status:, body_sent:, content_length:)
      write_answer_head(status, "Content-Length" => content_length.to_s)
      @socket.write(body_sent)
      @socket.close
    end

    def open_event_stream
      @socket.write("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nTransfer-Encoding: chunked\r\n\r\n")
    end

    def send_event(data, id: nil)
      send_stream_text("#{"id: #{id}\n" unless id.nil?}data: #{data}\n\n")
    end

    def send_stream_text(text)
      @socket.write("#{text.bytesize.to_s(16)}\r\n#{text}\r\n")
    end

    def end_event_stream
      @socket.write("0\r\n\r\n")
      @socket.close
    end

    def drop
      @socket.close
    end

    private

    def write_answer_head(status, headers)
      header_lines = headers.merge("Connection" => "close").map { |name, value| "#{name}: #{value}\r\n" }
      @socket.write("HTTP/1.1 #{status} Scripted\r\n#{header_lines.join}\r\n")
    end
  end

  def self.url_nothing_listens_on
    listener = TCPServer.new("127.0.0.1", 0)
    port = listener.addr[1]
    listener.close

    "http://127.0.0.1:#{port}"
  end

  def initialize
    @listener = TCPServer.new("127.0.0.1", 0)
    @port = @listener.addr[1]
    @lock = Mutex.new
    @held_requests_by_path = {}
    @holds_telemetry_reports = false
    @sockets = []
    @request_readers = []
    @acceptor = Thread.new { accept_connections }
    @acceptor.name = "scripted-sdk-server"
  end

  def url
    "http://127.0.0.1:#{@port}"
  end

  def next_request_to(path, within: 5)
    request = request_to(path, within: within)
    raise "The scripted SDK server received no request to #{path} within #{within} seconds" if request.nil?

    request
  end

  def request_to(path, within:)
    held_requests_to(path).pop(timeout: within)
  end

  def next_stream_request(within: 5)
    next_request_to(STREAM_PATH, within: within)
  end

  def next_heartbeat_request(within: 5)
    next_request_to(HEARTBEAT_PATH, within: within)
  end

  def next_poll_request(within: 5)
    next_request_to(POLLING_PATH, within: within)
  end

  def next_telemetry_request(within: 5)
    next_request_to(TELEMETRY_PATH, within: within)
  end

  def hold_telemetry_reports
    @lock.synchronize { @holds_telemetry_reports = true }
  end

  def receives_a_request_to?(path, within:)
    !request_to(path, within: within).nil?
  end

  def stop
    @listener.close
    @acceptor.join
    sockets, request_readers = @lock.synchronize { [@sockets.dup, @request_readers.dup] }
    sockets.each { |socket| socket.close unless socket.closed? }
    request_readers.each(&:join)
  end

  private

  def held_requests_to(path)
    @lock.synchronize { @held_requests_by_path[path] ||= Queue.new }
  end

  def accept_connections
    loop do
      socket = @listener.accept
      @lock.synchronize do
        @sockets << socket
        @request_readers << Thread.new { hold_the_request_on(socket) }
      end
    end
  rescue IOError, SystemCallError
    nil
  end

  def hold_the_request_on(socket)
    _http_method, path, _http_version = socket.gets("\r\n").to_s.split
    headers = header_lines_on(socket).to_h { |line| line.split(": ", 2) }.transform_keys(&:downcase)
    body = socket.read(Integer(headers.fetch("content-length", "0")))
    hold_or_accept_at_once(HeldRequest.new(socket, path, headers, body)) unless path.nil?
  rescue IOError, SystemCallError
    nil
  end

  def hold_or_accept_at_once(request)
    accepted_at_once = accepts_at_once?(request.path)
    held_requests_to(request.path) << request
    request.answer(status: 204) if accepted_at_once
  end

  def accepts_at_once?(path)
    path == TELEMETRY_PATH && !@lock.synchronize { @holds_telemetry_reports }
  end

  def header_lines_on(socket)
    lines = []
    while (line = socket.gets("\r\n").to_s.chomp) != ""
      lines << line
    end
    lines
  end
end
