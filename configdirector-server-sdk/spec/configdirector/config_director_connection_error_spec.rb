# frozen_string_literal: true

RSpec.describe ConfigDirector::ConfigDirectorConnectionError do
  it "is a ConfigDirectorError" do
    expect(described_class.new("Connection failed with status: 401.", status: 401))
      .to be_a(ConfigDirector::ConfigDirectorError)
  end

  it "has the HTTP status it was given" do
    error = described_class.new("Connection failed with status: 401.", status: 401)

    expect(error.status).to eq(401)
  end

  it "has the message it was given" do
    error = described_class.new("Connection failed with status: 401.", status: 401)

    expect(error.message).to eq("Connection failed with status: 401.")
  end

  it "has no status when none was given" do
    error = described_class.new("The SDK server gave no answer.")

    expect(error.status).to be_nil
  end

  it "can be raised with a message alone" do
    expect { raise described_class, "The SDK server gave no answer." }
      .to raise_error(described_class, "The SDK server gave no answer.")
  end
end
