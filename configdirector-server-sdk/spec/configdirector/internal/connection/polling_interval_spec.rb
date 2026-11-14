# frozen_string_literal: true

RSpec.describe ConfigDirector::Internal::Connection::PollingInterval do
  it "raises 30 seconds to 60 seconds" do
    polling_interval = described_class.new(configured_seconds: 30)

    expect(polling_interval.seconds).to eq(60)
    expect(polling_interval.raised_to_the_minimum?).to be(true)
  end

  it "raises a negative interval to 60 seconds" do
    polling_interval = described_class.new(configured_seconds: -5)

    expect(polling_interval.seconds).to eq(60)
    expect(polling_interval.raised_to_the_minimum?).to be(true)
  end

  it "keeps 60 seconds" do
    polling_interval = described_class.new(configured_seconds: 60)

    expect(polling_interval.seconds).to eq(60)
    expect(polling_interval.raised_to_the_minimum?).to be(false)
  end

  it "keeps 120.5 seconds" do
    polling_interval = described_class.new(configured_seconds: 120.5)

    expect(polling_interval.seconds).to eq(120.5)
    expect(polling_interval.raised_to_the_minimum?).to be(false)
  end
end
