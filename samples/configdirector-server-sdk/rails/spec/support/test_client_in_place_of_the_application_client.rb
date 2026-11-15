# frozen_string_literal: true

RSpec.shared_context "with a test client in place of the client the application creates" do
  let(:test_client) { ConfigDirector::Testing.create_test_client(FiveStandardConfigs::VALUES, logger: Rails.logger) }

  before { allow(ConfigDirector).to receive(:create_client).and_return(test_client.client) }
end
