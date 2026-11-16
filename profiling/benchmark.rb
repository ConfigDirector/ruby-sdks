# frozen_string_literal: true

require_relative "workload"

module ReadBenchmark
  READS = 200_000
  READS_BEFORE_THE_MEASUREMENT = 20_000
  READING_THREADS = 16
  PAYLOADS_TAKEN_IN = 200
  CLIENTS_INITIALIZED = 50
  CONTEXTS = Array.new(500) { |number| Workload.context_of_user(number) }.freeze

  def self.run
    payload_text = Workload.payload_text
    sdk_server, stream_requests = Workload.sdk_server_opening_every_stream_with(payload_text)
    puts Workload.description_of_the_machine, description_of_the_run(payload_text), ""
    puts line_about_init(sdk_server.url)
    puts lines_about_a_client_initialized_against(sdk_server.url, stream_requests, payload_text)
    sdk_server.stop
  end

  def self.lines_about_a_client_initialized_against(sdk_server_url, stream_requests, payload_text)
    client = Workload.client_of(sdk_server_url)
    client.init
    lines = lines_about_reads(client) + [
      line_about_payloads(client, last_stream_opened(stream_requests), payload_text)
    ]
    client.close
    lines
  end

  def self.description_of_the_run(payload_text)
    yjit = defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled? ? "on" : "off"

    "YJIT #{yjit}, a full payload of #{Workload::CONFIG_COUNT} configs in #{payload_text.bytesize} bytes"
  end

  def self.last_stream_opened(stream_requests)
    stream_request = stream_requests.pop
    stream_request = stream_requests.pop until stream_requests.empty?
    stream_request
  end

  def self.line_about_init(sdk_server_url)
    milliseconds = Array.new(CLIENTS_INITIALIZED) do
      client = Workload.client_of(sdk_server_url)
      seconds = Workload.seconds_taken { client.init }
      client.close
      seconds * 1000
    end

    format("init against the local server:    median %<median>.2f ms, slowest %<slowest>.2f ms, %<count>d clients",
           median: Workload.median_of(milliseconds), slowest: milliseconds.max, count: CLIENTS_INITIALIZED)
  end

  def self.read(client, reads)
    reads.times do |index|
      client.get_value(
        Workload::CONFIG_KEYS[index % Workload::CONFIG_COUNT], "in-code", CONTEXTS[index % CONTEXTS.length]
      )
    end
  end

  def self.lines_about_reads(client)
    read(client, READS_BEFORE_THE_MEASUREMENT)
    seconds_on_one_thread = Workload.seconds_taken { read(client, READS) }
    seconds_on_every_thread = Workload.seconds_taken do
      Array.new(READING_THREADS) { Thread.new { read(client, READS / READING_THREADS) } }.each(&:join)
    end

    [
      "get_value on one thread:          #{cost_of_a_read_taking(seconds_on_one_thread)}",
      "get_value on #{READING_THREADS} threads at once:  #{cost_of_a_read_taking(seconds_on_every_thread)} in all"
    ]
  end

  def self.cost_of_a_read_taking(seconds_for_every_read)
    format("%<microseconds>.2f microseconds a read, %<rate>d reads a second",
           microseconds: seconds_for_every_read / READS * 1_000_000, rate: READS / seconds_for_every_read)
  end

  def self.line_about_payloads(client, stream_request, payload_text)
    updates = Queue.new
    client.on(:configs_updated) { |update| updates << update }
    seconds = Workload.seconds_taken do
      PAYLOADS_TAKEN_IN.times do
        stream_request.send_event(payload_text)
        updates.pop
      end
    end

    format("taking in a full payload:         %<milliseconds>.2f ms from the SDK server's write to the handler",
           milliseconds: seconds / PAYLOADS_TAKEN_IN * 1000)
  end

  private_constant :READS, :READS_BEFORE_THE_MEASUREMENT, :READING_THREADS, :PAYLOADS_TAKEN_IN, :CLIENTS_INITIALIZED,
                   :CONTEXTS
  private_class_method :lines_about_a_client_initialized_against, :description_of_the_run, :last_stream_opened,
                       :line_about_init, :read, :lines_about_reads, :cost_of_a_read_taking, :line_about_payloads
end

ReadBenchmark.run
