# frozen_string_literal: true

RSpec.describe "The ConfigDirector client of a process", type: :request do
  it "reads the configs of every request through the same client" do
    evaluated_keys = []
    ConfigDirectorClientPerProcess.client.on(:config_evaluated) { |event| evaluated_keys << event.evaluation.key }

    get "/configs"
    get "/configs"

    expect(evaluated_keys).to eq(
      %w[
        temporary-feature-flag permanent-kill-switch integer-config day-of-the-week-config json-value-config
        temporary-feature-flag permanent-kill-switch integer-config day-of-the-week-config json-value-config
      ]
    )
  end

  it "is created once when the first two requests of a process arrive together" do
    threads_creating_a_client = Queue.new
    second_creation = Queue.new
    allow(ConfigDirector).to receive(:create_client).and_wrap_original do |create_client, *arguments, **options|
      first_creation = threads_creating_a_client.empty?
      threads_creating_a_client << Thread.current
      if first_creation
        second_creation.pop(timeout: 0.5)
      else
        second_creation << :arrived
      end
      create_client.call(*arguments, **options)
    end

    statuses = Array.new(2) do
      Thread.new { Rack::MockRequest.new(Rails.application).get("/configs").status }
    end.map(&:value)

    expect(statuses).to eq([200, 200])
    expect(threads_creating_a_client.size).to eq(1)
  end
end
