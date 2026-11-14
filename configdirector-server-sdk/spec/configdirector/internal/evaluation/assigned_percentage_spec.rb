# frozen_string_literal: true

RSpec.describe ConfigDirector::Internal::Evaluation::AssignedPercentage do
  contract_config_id = "11111111-1111-4111-8111-111111111111"

  it "hashes the identifier, then the config id" do
    expect(described_class.of("00000000-0000-0000-0000-000000000001", "abc", "user")).to eq(61.8)
  end

  it "assigns another percentage for another config id" do
    expect(described_class.of("00000000-0000-0000-0000-0000000003e8", "abc", "user")).to eq(34.0)
  end

  it "takes a numeric identifier's percentage from its text" do
    expect(described_class.of("00000000-0000-0000-0000-0000000007d0", "378368375", "user")).to eq(13.5)
  end

  it "lands the next identifier elsewhere" do
    expect(described_class.of("00000000-0000-0000-0000-0000000003e8", "378368376", "user")).to eq(66.0)
  end

  it "assigns a user the contract's user vector" do
    expect(described_class.of(contract_config_id, "user-1", "user")).to eq(7.8)
  end

  it "appends the kind to the input of a device" do
    expect(described_class.of(contract_config_id, "user-1", "device")).to eq(59.0)
  end

  it "lands a tenant elsewhere than a device with the same identifier" do
    expect(described_class.of(contract_config_id, "user-1", "tenant")).to eq(8.5)
  end

  it "assigns another device the contract's device vector" do
    expect(described_class.of(contract_config_id, "abc", "device")).to eq(75.0)
  end

  it "assigns the contract's boundary identifier exactly fifty percent" do
    expect(described_class.of(contract_config_id, "u582", "user")).to eq(50.0)
  end
end
