# frozen_string_literal: true

require_relative "client_of_the_scripted_sdk_server"
require_relative "waiting"

class StreamsPublishedTo
  include Waiting

  def initialize(sdk_server, first_payload_text)
    @sdk_server = sdk_server
    @lock = Mutex.new
    @stream_requests = []
    @published_payload_text = first_payload_text
    @thread_opening_every_stream = Thread.new { open_every_stream_requested }
  end

  def publish(payload_text)
    @lock.synchronize do
      @published_payload_text = payload_text
      @stream_requests.each { |stream_request| send_to(stream_request, payload_text) }
    end
  end

  def session_ids_once_there_are(count, within: 5)
    wait_up_to(within) { session_ids.length >= count }

    session_ids
  end

  def session_ids
    @lock.synchronize { @stream_requests.map { |stream_request| stream_request.json.fetch("sessionId") } }
  end

  def stop
    @thread_opening_every_stream.kill.join
  end

  private

  def open_every_stream_requested
    loop do
      stream_request = @sdk_server.request_to(ScriptedSdkServer::STREAM_PATH, within: nil)
      @lock.synchronize do
        stream_request.open_event_stream
        stream_request.send_event(@published_payload_text)
        @stream_requests << stream_request
      end
    end
  end

  def send_to(stream_request, payload_text)
    stream_request.send_event(payload_text)
  rescue IOError, SystemCallError
    nil
  end
end

RSpec.shared_context "with an SDK server that publishes to every stream" do
  include_context "with a client of the scripted SDK server"

  let(:streams_published_to) { [] }

  after { streams_published_to.each(&:stop) }

  def streams_opened_with(first_payload_text)
    streams = StreamsPublishedTo.new(sdk_server, first_payload_text)
    streams_published_to << streams
    streams
  end
end
