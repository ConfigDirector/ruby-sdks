# frozen_string_literal: true

require "socket"

class LocalSdkServer
  STREAM_PATH = "/server/sse/v1"
  POLLING_PATH = "/server/polling/v1"

  def initialize(payload_text)
    @payload_text = payload_text
    @listener = TCPServer.new("127.0.0.1", 0)
    @lock = Mutex.new
    @sockets = []
    @acceptor = Thread.new { accept_connections }
  end

  def url
    "http://127.0.0.1:#{@listener.addr[1]}"
  end

  def stop
    @listener.close
    @acceptor.join
    @lock.synchronize { @sockets.dup }.each { |socket| socket.close unless socket.closed? }
  end

  private

  def accept_connections
    loop do
      socket = @listener.accept
      @lock.synchronize { @sockets << socket }
      Thread.new { answer_the_request_on(socket) }
    end
  rescue IOError, SystemCallError
    nil
  end

  def answer_the_request_on(socket)
    case path_of_the_request_on(socket)
    when STREAM_PATH then open_a_stream_of_the_payload_on(socket)
    when POLLING_PATH then answer_with_the_payload_on(socket)
    else answer_without_content_on(socket)
    end
  rescue IOError, SystemCallError
    nil
  end

  def path_of_the_request_on(socket)
    _http_method, path, _http_version = socket.gets("\r\n").to_s.split
    content_length = 0
    while (header_line = socket.gets("\r\n").to_s.chomp) != ""
      name, value = header_line.split(": ", 2)
      content_length = Integer(value) if name.casecmp?("content-length")
    end
    socket.read(content_length)

    path
  end

  def open_a_stream_of_the_payload_on(socket)
    event = "data: #{@payload_text}\n\n"
    socket.write("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nTransfer-Encoding: chunked\r\n\r\n")
    socket.write("#{event.bytesize.to_s(16)}\r\n#{event}\r\n")
  end

  def answer_with_the_payload_on(socket)
    socket.write(
      "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: #{@payload_text.bytesize}\r\n" \
      "Connection: close\r\n\r\n#{@payload_text}"
    )
    socket.close
  end

  def answer_without_content_on(socket)
    socket.write("HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n")
    socket.close
  end
end
