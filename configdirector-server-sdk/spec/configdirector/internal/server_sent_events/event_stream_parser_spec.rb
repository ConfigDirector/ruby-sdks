# frozen_string_literal: true

RSpec.describe ConfigDirector::Internal::ServerSentEvents::EventStreamParser do
  def parser_collecting_into(events)
    described_class.new(last_event_id: "") { |event| events << event }
  end

  def parser_discarding_events
    described_class.new(last_event_id: "") { |_event| nil }
  end

  def event(type, data)
    ConfigDirector::Internal::ServerSentEvents::ServerSentEvent.new(type: type, data: data)
  end

  def data_line_of_bytes(line_bytes)
    "data: #{"x" * (line_bytes - "data: ".bytesize)}"
  end

  def data_lines_holding_bytes(data_bytes)
    longest_value_of_a_line = 1_048_576 - "data: ".bytesize
    lines = []
    bytes_left = data_bytes
    while bytes_left > longest_value_of_a_line
      lines << "data: #{"x" * longest_value_of_a_line}"
      bytes_left -= longest_value_of_a_line + "\n".bytesize
    end
    lines << "data: #{"x" * bytes_left}"
    "#{lines.join("\n")}\n"
  end

  it "joins the data lines of an event with newlines" do
    events = []
    parser = parser_collecting_into(events)

    parser.feed("data: first line\ndata: second line\ndata: third line\n\n")

    expect(events).to eq([event("", "first line\nsecond line\nthird line")])
  end

  it "names the event from its event field" do
    events = []
    parser = parser_collecting_into(events)

    parser.feed("event: payload\ndata: {}\n\n")

    expect(events).to eq([event("payload", "{}")])
  end

  it "does not carry the name of an event over to the next event" do
    events = []
    parser = parser_collecting_into(events)

    parser.feed("event: payload\ndata: first\n\ndata: second\n\n")

    expect(events).to eq([event("payload", "first"), event("", "second")])
  end

  it "leaves only the first space after the colon out of the value" do
    events = []
    parser = parser_collecting_into(events)

    parser.feed("data:  indented\n\n")

    expect(events).to eq([event("", " indented")])
  end

  it "reads a value without a space after the colon whole" do
    events = []
    parser = parser_collecting_into(events)

    parser.feed("data:unspaced\n\n")

    expect(events).to eq([event("", "unspaced")])
  end

  it "dispatches no event without a data field" do
    events = []
    parser = parser_collecting_into(events)

    parser.feed("event: payload\nid: 42\n\n")

    expect(events).to eq([])
  end

  it "dispatches no event whose data is empty" do
    events = []
    parser = parser_collecting_into(events)

    parser.feed("event: payload\ndata:\n\n")

    expect(events).to eq([])
  end

  it "keeps the last event ID the previous connection reached until the server sends an ID" do
    parser = described_class.new(last_event_id: "41") { |_event| nil }

    parser.feed("data: first\n\n")

    expect(parser.last_event_id).to eq("41")
  end

  it "sets the last event ID from the id field" do
    parser = parser_discarding_events

    parser.feed("id: 41\ndata: first\n\nid: 42\ndata: second\n\n")

    expect(parser.last_event_id).to eq("42")
  end

  it "keeps the last event ID after an event without an ID" do
    parser = parser_discarding_events

    parser.feed("id: 42\ndata: first\n\ndata: second\n\n")

    expect(parser.last_event_id).to eq("42")
  end

  it "ignores an ID containing a NUL" do
    parser = parser_discarding_events

    parser.feed("id: 42\ndata: first\n\nid: 4\u00003\ndata: second\n\n")

    expect(parser.last_event_id).to eq("42")
  end

  it "knows no retry until the server sends one" do
    parser = parser_discarding_events

    parser.feed("data: first\n\n")

    expect(parser.retry_milliseconds).to be_nil
  end

  it "reads a retry of ASCII digits as milliseconds" do
    parser = parser_discarding_events

    parser.feed("retry: 2500\n")

    expect(parser.retry_milliseconds).to eq(2500)
  end

  it "ignores a retry with a unit" do
    parser = parser_discarding_events

    parser.feed("retry: 2500\nretry: 3s\n")

    expect(parser.retry_milliseconds).to eq(2500)
  end

  it "ignores a negative retry" do
    parser = parser_discarding_events

    parser.feed("retry: 2500\nretry: -1\n")

    expect(parser.retry_milliseconds).to eq(2500)
  end

  it "ignores a retry written in digits outside ASCII" do
    parser = parser_discarding_events

    parser.feed("retry: 2500\nretry: ３０００\n")

    expect(parser.retry_milliseconds).to eq(2500)
  end

  it "dispatches no event for the keepalive comment of the SDK server" do
    events = []
    parser = parser_collecting_into(events)

    parser.feed(":\n\n: keepalive\n\n")

    expect(events).to eq([])
  end

  it "leaves the data of an event whole around a comment between its data lines" do
    events = []
    parser = parser_collecting_into(events)

    parser.feed("data: first line\n:\n: keepalive\ndata: second line\n\n")

    expect(events).to eq([event("", "first line\nsecond line")])
  end

  it "ends a line on a carriage return followed by a line feed" do
    events = []
    parser = parser_collecting_into(events)

    parser.feed("data: first line\r\ndata: second line\r\n\r\n")

    expect(events).to eq([event("", "first line\nsecond line")])
  end

  it "ends a line on a carriage return alone" do
    events = []
    parser = parser_collecting_into(events)

    parser.feed("data: first line\rdata: second line\r\r")

    expect(events).to eq([event("", "first line\nsecond line")])
  end

  it "ends one line on a carriage return and a line feed split across two chunks" do
    events = []
    parser = parser_collecting_into(events)

    parser.feed("data: first line\r")
    parser.feed("\ndata: second line\r\n\r\n")

    expect(events).to eq([event("", "first line\nsecond line")])
  end

  it "ends one line on a carriage return and a line feed with an empty chunk between them" do
    events = []
    parser = parser_collecting_into(events)

    parser.feed("data: first line\r")
    parser.feed("")
    parser.feed("\ndata: second line\r\n\r\n")

    expect(events).to eq([event("", "first line\nsecond line")])
  end

  it "dispatches an event split across three chunks whole" do
    events = []
    parser = parser_collecting_into(events)

    parser.feed("event: payload\ndata: {\"kind\": \"fu")
    parser.feed("ll\", \"con")
    parser.feed("figs\": {}}\n\n")

    expect(events).to eq([event("payload", '{"kind": "full", "configs": {}}')])
  end

  it "reads a character whose UTF-8 bytes are split across two chunks whole" do
    events = []
    parser = parser_collecting_into(events)

    parser.feed("data: caf\xC3".b)
    parser.feed("\xA9\n\n".b)

    expect(events).to eq([event("", "café")])
  end

  it "reads a byte that is not UTF-8 as a replacement character" do
    events = []
    parser = parser_collecting_into(events)

    parser.feed("data: caf\xFF\n\n".b)

    expect(events).to eq([event("", "caf\uFFFD")])
  end

  it "drops a byte order mark that starts the stream" do
    events = []
    parser = parser_collecting_into(events)

    parser.feed("\xEF\xBB\xBFdata: first\n\n".b)

    expect(events).to eq([event("", "first")])
  end

  it "reads a byte order mark that starts a later line as part of its field name" do
    events = []
    parser = parser_collecting_into(events)

    parser.feed("data: first\n\n\xEF\xBB\xBFdata: second\n\n".b)

    expect(events).to eq([event("", "first")])
  end

  it "dispatches no partial event when the stream is cut mid-event" do
    events = []
    parser = parser_collecting_into(events)

    parser.feed("data: complete\n\ndata: cut off\n")

    expect(events).to eq([event("", "complete")])
  end

  it "rejects a line of 1 MiB plus one byte" do
    parser = parser_discarding_events

    expect { parser.feed("#{data_line_of_bytes(1_048_577)}\n\n") }
      .to raise_error(ConfigDirector::Internal::ServerSentEvents::EventStreamLimitExceeded)
  end

  it "reads a line of exactly 1 MiB" do
    events = []
    parser = parser_collecting_into(events)

    parser.feed("#{data_line_of_bytes(1_048_576)}\n\n")

    expect(events.map { |dispatched| dispatched.data.bytesize }).to eq([1_048_570])
  end

  it "rejects a line that never ends once it holds more than 1 MiB" do
    parser = parser_discarding_events
    parser.feed("x" * 1_048_576)

    expect { parser.feed("x") }.to raise_error(ConfigDirector::Internal::ServerSentEvents::EventStreamLimitExceeded)
  end

  it "counts the line limit in bytes, not characters" do
    parser = parser_discarding_events

    expect { parser.feed("data: #{"€" * 349_524}\n\n") }
      .to raise_error(ConfigDirector::Internal::ServerSentEvents::EventStreamLimitExceeded)
  end

  it "rejects an event of 16 MiB plus one byte" do
    parser = parser_discarding_events

    expect { parser.feed("#{data_lines_holding_bytes(16_777_217)}\n") }
      .to raise_error(ConfigDirector::Internal::ServerSentEvents::EventStreamLimitExceeded)
  end

  it "reads an event of exactly 16 MiB" do
    events = []
    parser = parser_collecting_into(events)

    parser.feed("#{data_lines_holding_bytes(16_777_216)}\n")

    expect(events.map { |dispatched| dispatched.data.bytesize }).to eq([16_777_216])
  end

  it "dispatches the events that ended before a limit was exceeded in the same chunk" do
    events = []
    parser = parser_collecting_into(events)

    expect { parser.feed("data: complete\n\n#{data_line_of_bytes(1_048_577)}\n\n") }
      .to raise_error(ConfigDirector::Internal::ServerSentEvents::EventStreamLimitExceeded)
    expect(events).to eq([event("", "complete")])
  end
end
