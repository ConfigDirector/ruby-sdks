# frozen_string_literal: true

module ConfigDirector
  module Internal
    module ServerSentEvents
      class EventStreamParser
        MAXIMUM_LINE_BYTES = 1_048_576
        MAXIMUM_EVENT_DATA_BYTES = 16_777_216
        LINE_END = /[\r\n]/
        BYTE_ORDER_MARK = "\uFEFF"
        ASCII_DIGITS = /\A[0-9]+\z/

        private_constant :MAXIMUM_LINE_BYTES, :MAXIMUM_EVENT_DATA_BYTES, :LINE_END, :BYTE_ORDER_MARK, :ASCII_DIGITS

        attr_reader :last_event_id, :retry_milliseconds

        def initialize(last_event_id:, &on_event)
          @last_event_id = last_event_id
          @on_event = on_event
          @at_the_start_of_the_stream = true
          @unfinished_line = String.new(encoding: Encoding::BINARY)
          @last_chunk_ended_on_a_carriage_return = false
          @event_type = ""
          @event_data = String.new(encoding: Encoding::UTF_8)
          @retry_milliseconds = nil
        end

        def feed(chunk)
          return if chunk.empty?

          bytes = chunk.b
          line_start = @last_chunk_ended_on_a_carriage_return && bytes.start_with?("\n") ? 1 : 0
          @last_chunk_ended_on_a_carriage_return = bytes.end_with?("\r")
          while (line_end = bytes.byteindex(LINE_END, line_start))
            finish_line(bytes.byteslice(line_start, line_end - line_start).to_s)
            line_start = line_end + (bytes.byteslice(line_end, 2) == "\r\n" ? 2 : 1)
          end
          extend_unfinished_line(bytes.byteslice(line_start..).to_s)
        end

        private

        def extend_unfinished_line(fragment)
          if @unfinished_line.bytesize + fragment.bytesize > MAXIMUM_LINE_BYTES
            raise EventStreamLimitExceeded, "The SDK server sent a line longer than 1 MiB."
          end

          @unfinished_line << fragment
        end

        def finish_line(fragment)
          extend_unfinished_line(fragment)
          line = @unfinished_line.force_encoding(Encoding::UTF_8).scrub!
          @unfinished_line = String.new(encoding: Encoding::BINARY)
          line = line.delete_prefix(BYTE_ORDER_MARK) if @at_the_start_of_the_stream
          @at_the_start_of_the_stream = false
          read_line(line)
        end

        def read_line(line)
          return dispatch_event if line.empty?

          name, _colon, value = line.partition(":")
          read_field(name, value.delete_prefix(" "))
        end

        def read_field(name, value)
          case name
          when "event" then @event_type = value
          when "data" then append_data(value)
          when "id" then @last_event_id = value unless value.include?("\0")
          when "retry" then @retry_milliseconds = Integer(value, 10) if value.match?(ASCII_DIGITS)
          end
        end

        def append_data(value)
          if @event_data.bytesize + value.bytesize > MAXIMUM_EVENT_DATA_BYTES
            raise EventStreamLimitExceeded, "The SDK server sent an event larger than 16 MiB."
          end

          @event_data << value << "\n"
        end

        def dispatch_event
          data = @event_data
          data.delete_suffix!("\n")
          event = ServerSentEvent.new(type: @event_type, data: data)
          @event_type = ""
          @event_data = String.new(encoding: Encoding::UTF_8)
          @on_event.call(event) unless event.data.empty?
        end
      end
    end
  end
end
