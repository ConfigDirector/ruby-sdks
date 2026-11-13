# frozen_string_literal: true

RSpec.describe ConfigDirector::OpenFeature do
  it "has a VERSION that is a semantic version without a prefix" do
    expect(ConfigDirector::OpenFeature::VERSION).to match(/\A[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?\z/)
  end
end
