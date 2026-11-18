# frozen_string_literal: true

RSpec.shared_context "with the standard output captured as the log" do
  let(:log) { StringIO.new }

  around do |example|
    standard_output = $stdout
    $stdout = log
    example.run
  ensure
    $stdout = standard_output
  end
end
