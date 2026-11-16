# frozen_string_literal: true

RSpec.describe ConfigDirector::Internal::Telemetry::ValueId do
  it "is the first 16 bytes of the SHA-256 digest of the text, in base62" do
    expect(described_class.of('{"greeting":"hi"}')).to eq("2nSU077zdp6QUP84OcTEOx")
  end

  it "is padded with zeros to 22 characters" do
    expect(described_class.of("padded-1")).to eq("0mQjuefE6ijlIS9uMHizDw")
  end

  it "is the ID of the bytes of a text that is not ASCII" do
    expect(described_class.of('["é"]')).to eq("0LVIDhf5GPmBEiBZxqjRVS")
  end
end
