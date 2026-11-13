# frozen_string_literal: true

RSpec.describe ConfigDirector do
  it "has a VERSION that is a semantic version without a prefix" do
    expect(ConfigDirector::VERSION).to match(/\A[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?\z/)
  end
end
