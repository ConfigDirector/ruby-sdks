# frozen_string_literal: true

class ScriptedConnection
  attr_reader :open_count, :close_count

  def initialize(payloads_delivered_when_opened: [], opening_held: false)
    @payloads_delivered_when_opened = payloads_delivered_when_opened
    @opening_held = opening_held
    @opening = Queue.new
    @opening_released = Queue.new
    @opened = Queue.new
    @open_count = 0
    @close_count = 0
  end

  def open(&deliver_payload)
    @open_count += 1
    @deliver_payload = deliver_payload
    @opening << true
    @opening_released.pop if @opening_held
    @payloads_delivered_when_opened.each { |payload| deliver_payload.call(payload) }
    @opened << true
  end

  def close
    @close_count += 1
  end

  def wait_until_opening
    @opening.pop
  end

  def release_opening
    @opening_released << true
  end

  def wait_until_opened
    @opened.pop
  end

  def deliver(payload)
    @deliver_payload.call(payload)
  end
end
