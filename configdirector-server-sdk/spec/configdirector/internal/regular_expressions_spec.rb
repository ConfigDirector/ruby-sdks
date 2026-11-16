# frozen_string_literal: true

require "time"
require_relative "../../support/elapsed_seconds"

RSpec.describe "Each regular expression of the SDK, on 100,000 characters written to make it backtrack" do
  include ElapsedSeconds

  let(:digits) { "9" * 100_000 }
  let(:most_seconds_a_match_may_take) { 1 }

  def event_stream_parser
    ConfigDirector::Internal::ServerSentEvents::EventStreamParser.new(last_event_id: "") { |_event| nil }
  end

  it "finds the line ends of an event stream of 100,000 carriage returns" do
    seconds = seconds_taken { event_stream_parser.feed("\r" * 100_000) }

    expect(seconds).to be < most_seconds_a_match_may_take
  end

  it "reads a retry field of 100,000 digits" do
    seconds = seconds_taken { event_stream_parser.feed("retry: #{digits}\n\n") }

    expect(seconds).to be < most_seconds_a_match_may_take
  end

  it "reads a retry field of 100,000 digits and a letter" do
    seconds = seconds_taken { event_stream_parser.feed("retry: #{digits}x\n\n") }

    expect(seconds).to be < most_seconds_a_match_may_take
  end

  it "reads a Retry-After header of 100,000 digits and a letter" do
    seconds = seconds_taken do
      ConfigDirector::Internal::Connection::RetryAfterHeader.seconds_to_wait("#{digits}x", Time.now)
    end

    expect(seconds).to be < most_seconds_a_match_may_take
  end

  it "reads a Retry-After header of 100,000 spaces and a letter" do
    seconds = seconds_taken do
      ConfigDirector::Internal::Connection::RetryAfterHeader.seconds_to_wait("#{" " * 100_000}x", Time.now)
    end

    expect(seconds).to be < most_seconds_a_match_may_take
  end

  it "writes the smallest Float, the longest one in plain decimal text" do
    seconds = seconds_taken { ConfigDirector::Internal::Value::PlainDecimalText.of(5.0e-324) }

    expect(seconds).to be < most_seconds_a_match_may_take
  end

  it "reads a whole number of 100,000 digits and a letter" do
    seconds = seconds_taken do
      ConfigDirector::Internal::Value::ServedText.typed_as(:integer, "#{digits}x", "integer")
    end

    expect(seconds).to be < most_seconds_a_match_may_take
  end

  it "reads a date and time with a fraction of 100,000 digits and a letter" do
    seconds = seconds_taken do
      ConfigDirector::Internal::Evaluation::DatetimeComparison.matches?(
        "2026-01-01T00:00:00.#{digits}x", "is before", ["2026-01-01"]
      )
    end

    expect(seconds).to be < most_seconds_a_match_may_take
  end

  it "reads a date and time with a fraction of 100,000 digits and an offset cut short" do
    seconds = seconds_taken do
      ConfigDirector::Internal::Evaluation::DatetimeComparison.matches?(
        "2026-01-01T00:00:00.#{digits}+99:9", "is after", ["2026-01-01"]
      )
    end

    expect(seconds).to be < most_seconds_a_match_may_take
  end

  it "reads a decimal number of 100,000 digits and a letter" do
    seconds = seconds_taken do
      ConfigDirector::Internal::Evaluation::NumberComparison.matches?("#{digits}.#{digits}x", "=", ["1"])
    end

    expect(seconds).to be < most_seconds_a_match_may_take
  end

  it "reads a decimal number with an exponent of 100,000 digits" do
    seconds = seconds_taken do
      ConfigDirector::Internal::Evaluation::NumberComparison.matches?("1e-#{digits}", "<", ["1e#{digits}x"])
    end

    expect(seconds).to be < most_seconds_a_match_may_take
  end

  it "drops the 100,000 leading zeros of a decimal number" do
    seconds = seconds_taken do
      ConfigDirector::Internal::Evaluation::NumberComparison.matches?("#{"0" * 100_000}.5", "=", ["0.5"])
    end

    expect(seconds).to be < most_seconds_a_match_may_take
  end

  it "finds no version in 100,000 digits" do
    seconds = seconds_taken do
      ConfigDirector::Internal::Evaluation::SemverComparison.matches?(digits, "=", ["1.0.0"])
    end

    expect(seconds).to be < most_seconds_a_match_may_take
  end

  it "finds no version in runs of 17 digits" do
    seconds = seconds_taken do
      ConfigDirector::Internal::Evaluation::SemverComparison.matches?("#{"1" * 17}x" * 5_555, "=", ["1.0.0"])
    end

    expect(seconds).to be < most_seconds_a_match_may_take
  end

  it "finds the version at the start of 50,000 version parts" do
    seconds = seconds_taken do
      ConfigDirector::Internal::Evaluation::SemverComparison.matches?("1." * 50_000, ">=", ["1.0.0"])
    end

    expect(seconds).to be < most_seconds_a_match_may_take
  end

  it "finds the invalid escape in a trait pointer of 100,000 tildes" do
    seconds = seconds_taken do
      ConfigDirector::Internal::Evaluation::TraitPointer.value_at("/#{"~" * 100_000}", { "~" => 1 })
    end

    expect(seconds).to be < most_seconds_a_match_may_take
  end

  it "decodes the 50,000 escapes of a trait pointer" do
    seconds = seconds_taken do
      ConfigDirector::Internal::Evaluation::TraitPointer.value_at("/#{"~0~1" * 25_000}", { "~" => 1 })
    end

    expect(seconds).to be < most_seconds_a_match_may_take
  end

  it "reads an array index of 100,000 digits and a letter in a trait pointer" do
    seconds = seconds_taken do
      ConfigDirector::Internal::Evaluation::TraitPointer.value_at("/plans/#{digits}x", { "plans" => ["pro"] })
    end

    expect(seconds).to be < most_seconds_a_match_may_take
  end

  it "checks a context kind of 64 letters and 100,000 exclamation marks" do
    seconds = seconds_taken do
      ConfigDirector::Internal::Client::ContextKind.valid?("#{"a" * 64}#{"!" * 100_000}")
    end

    expect(seconds).to be < most_seconds_a_match_may_take
  end

  it "finds the strings of JSON text that holds 40,000 escaped quotes and 20,000 backslashes" do
    json_text = "[\"#{"\\\"" * 40_000}\", \"#{"\\\\" * 10_000}\", #{"7" * 16_385}]"

    seconds = seconds_taken do
      ConfigDirector::Internal::Value::ParsedJson.of(json_text)
    rescue JSON::ParserError
      nil
    end

    expect(seconds).to be < most_seconds_a_match_may_take
  end

  it "finds the comments of JSON text that holds 50,000 slashes" do
    json_text = "[#{"/ " * 50_000}#{"7" * 16_385}]"

    seconds = seconds_taken do
      ConfigDirector::Internal::Value::ParsedJson.of(json_text)
    rescue JSON::ParserError
      nil
    end

    expect(seconds).to be < most_seconds_a_match_may_take
  end
end
