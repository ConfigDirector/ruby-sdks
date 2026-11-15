# frozen_string_literal: true

require "json"
require "timeout"

class ForkedProcess
  def self.reporting(&work)
    report_reader, report_writer = IO.pipe
    process_id = fork { write_the_report_and_exit(report_writer, work) }
    report_writer.close

    new(process_id, report_reader)
  end

  def self.write_the_report_and_exit(report_writer, work)
    report_writer.write(JSON.generate("report" => work.call))
  rescue StandardError => e
    report_writer.write(JSON.generate("error" => "#{e.class}: #{e.message}"))
  ensure
    report_writer.close
    exit!(0)
  end

  private_class_method :write_the_report_and_exit

  def initialize(process_id, report_reader)
    @process_id = process_id
    @report_reader = report_reader
  end

  def report
    report_text = report_text_within(10)
    raise "The forked process #{@process_id} ended without a report" if report_text.empty?

    outcome = JSON.parse(report_text)
    raise "The forked process #{@process_id} raised #{outcome.fetch("error")}" if outcome.key?("error")

    outcome.fetch("report")
  end

  private

  def report_text_within(seconds)
    report_text = Timeout.timeout(seconds) { @report_reader.read }
    Process.wait(@process_id)

    report_text
  rescue Timeout::Error
    Process.kill("KILL", @process_id)
    Process.wait(@process_id)
    raise "The forked process #{@process_id} reported nothing within #{seconds} seconds"
  end
end
