# frozen_string_literal: true

require "socket"
require_relative "workload"

module ForkPerJobMeasurement
  JOBS = 200
  STREAM_PATH = ScriptedSdkServer::STREAM_PATH
  TELEMETRY_PATH = ScriptedSdkServer::TELEMETRY_PATH
  REQUEST_CUT_OFF_BY_THE_EXIT = :request_cut_off_by_the_exit
  SECONDS_OF_WORK_IN_A_LONGER_JOB = 0.05

  class MeasuringSdkServer
    Connection = Data.define(:what_it_asked_for, :evaluations_reported, :milliseconds_open)

    def initialize(payload_text)
      @payload_text = payload_text
      @listener = TCPServer.new("127.0.0.1", 0)
      @connections = Queue.new
      Thread.new { loop { serve(@listener.accept) } }
    end

    def url
      "http://127.0.0.1:#{@listener.addr[1]}"
    end

    def connections_so_far
      Array.new(@connections.length) { @connections.pop }
    end

    private

    def serve(socket)
      Thread.new do
        opened_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        path, body = request_on(socket)
        answer(socket, path)
        @connections << connection_ended(path, body, opened_at)
      rescue IOError, SystemCallError, JSON::ParserError
        @connections << Connection.new(
          what_it_asked_for: REQUEST_CUT_OFF_BY_THE_EXIT, evaluations_reported: 0, milliseconds_open: 0
        )
      end
    end

    def request_on(socket)
      path = socket.gets("\r\n").to_s.split[1]
      content_length = 0
      while (line = socket.gets("\r\n").to_s.chomp) != ""
        name, value = line.split(": ", 2)
        content_length = Integer(value, 10) if name.casecmp?("content-length")
      end

      [path, JSON.parse(socket.read(content_length).to_s)]
    end

    def answer(socket, path)
      path == STREAM_PATH ? stream_until_the_client_leaves(socket) : socket.write("HTTP/1.1 204 No Content\r\n\r\n")
      socket.close
    end

    def stream_until_the_client_leaves(socket)
      event = "data: #{@payload_text}\n\n"
      socket.write("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nTransfer-Encoding: chunked\r\n\r\n")
      socket.write("#{event.bytesize.to_s(16)}\r\n#{event}\r\n")
      socket.read
    end

    def connection_ended(path, body, opened_at)
      Connection.new(
        what_it_asked_for: path,
        evaluations_reported: body.dig("aggregatedEvents", "evaluatedConfig").to_a.sum { |entry| entry.fetch("count") },
        milliseconds_open: (Process.clock_gettime(Process::CLOCK_MONOTONIC) - opened_at) * 1000
      )
    end
  end

  READ = ->(client) { client.get_value("config-1", "in-code", Workload.context_of_user(1)) }
  JOBS_BY_DESCRIPTION = {
    "reads one config and exits" => READ,
    "reads one config, works for 50 ms and exits" => lambda do |client|
      READ.call(client)
      sleep(SECONDS_OF_WORK_IN_A_LONGER_JOB)
    end,
    "reads one config, works for 50 ms, closes the client and exits" => lambda do |client|
      READ.call(client)
      sleep(SECONDS_OF_WORK_IN_A_LONGER_JOB)
      client.close
    end
  }.freeze

  def self.run
    puts Workload.description_of_the_machine
    puts "#{JOBS} forks one after another, each forked process leaving with exit!", ""
    puts lines_about_a_parent_without_a_client, ""
    JOBS_BY_DESCRIPTION.each { |description, job| puts lines_about_a_parent_with_a_client(description, job), "" }
  end

  def self.lines_about_a_parent_without_a_client
    [
      "A parent without a client, for comparison, each job exits at once",
      line_about_the_jobs_taking(milliseconds_of_each_job { nil }),
      "A parent without a client, for comparison, each job works for 50 ms and exits",
      line_about_the_jobs_taking(milliseconds_of_each_job { sleep(SECONDS_OF_WORK_IN_A_LONGER_JOB) })
    ]
  end

  def self.lines_about_a_parent_with_a_client(description, job)
    sdk_server = MeasuringSdkServer.new(Workload.payload_text)
    client = Workload.client_of(sdk_server.url)
    client.init
    line_about_the_jobs = line_about_the_jobs_taking(milliseconds_of_each_job { job.call(client) })
    sleep(1)
    lines_about_the_connections = lines_about_what_the_sdk_server_saw_of(sdk_server.connections_so_far)
    client.close

    ["A parent with an initialized client, each job #{description}", line_about_the_jobs, *lines_about_the_connections]
  end

  def self.milliseconds_of_each_job
    Array.new(JOBS) do
      forked_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      process_id = fork do
        yield
        exit!(0)
      end
      Process.wait(process_id)

      (Process.clock_gettime(Process::CLOCK_MONOTONIC) - forked_at) * 1000
    end
  end

  def self.line_about_the_jobs_taking(milliseconds)
    format("  a job took %<median>.2f ms from fork to exit (median), %<slowest>.2f ms at most",
           median: Workload.median_of(milliseconds), slowest: milliseconds.max)
  end

  def self.lines_about_what_the_sdk_server_saw_of(connections)
    connections_by_what_they_asked_for = connections.group_by(&:what_it_asked_for)
    reports = connections_by_what_they_asked_for.fetch(TELEMETRY_PATH, [])
    connections_cut_off = connections_by_what_they_asked_for.fetch(REQUEST_CUT_OFF_BY_THE_EXIT, [])

    [
      line_about_the_streams(connections_by_what_they_asked_for.fetch(STREAM_PATH, [])),
      "  #{connections_cut_off.length} connections were cut off by the exit before their request",
      "  it received #{reports.length} telemetry reports, with #{reports.sum(&:evaluations_reported)} evaluations"
    ]
  end

  def self.line_about_the_streams(streams)
    return "  the SDK server opened no stream" if streams.empty?

    milliseconds_open = streams.map(&:milliseconds_open)
    format("  the SDK server opened %<count>d streams, each with the full payload, open %<median>.2f ms (median), " \
           "%<longest>.2f ms at most",
           count: streams.length, median: Workload.median_of(milliseconds_open), longest: milliseconds_open.max)
  end

  private_constant :JOBS, :STREAM_PATH, :TELEMETRY_PATH, :REQUEST_CUT_OFF_BY_THE_EXIT,
                   :SECONDS_OF_WORK_IN_A_LONGER_JOB, :MeasuringSdkServer, :READ, :JOBS_BY_DESCRIPTION
  private_class_method :lines_about_a_parent_without_a_client, :lines_about_a_parent_with_a_client,
                       :milliseconds_of_each_job, :line_about_the_jobs_taking, :lines_about_what_the_sdk_server_saw_of,
                       :line_about_the_streams
end

ForkPerJobMeasurement.run
