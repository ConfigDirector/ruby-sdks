# frozen_string_literal: true

require_relative "../support/recording_logger"
require_relative "../support/self_signed_tls_listener"

RSpec.describe "A client that connects over TLS" do
  let(:logger) { RecordingLogger.new }
  let(:tls_listener) { SelfSignedTlsListener.new }
  let(:clients_created) { [] }

  after do
    clients_created.each(&:close)
    tls_listener.close
  end

  def client_connecting_over_tls(mode)
    client = ConfigDirector.create_client(
      "server-sdk-key",
      connection: ConfigDirector::ConnectionOptions.new(mode: mode, timeout: 2, url: tls_listener.url), logger: logger
    )
    clients_created << client
    client
  end

  it "sends nothing over a stream to a server whose certificate no trusted authority signed" do
    connection = tls_listener.what_the_next_connection_brings
    client = client_connecting_over_tls("streaming")

    client.init

    expect(connection.value).to eq(:a_handshake_the_client_ended)
    expect(client.ready?).to be(false)
    expect(logger.messages_at(:debug).grep(/certificate verify failed/)).not_to be_empty
  end

  it "sends no poll to a server whose certificate no trusted authority signed" do
    connection = tls_listener.what_the_next_connection_brings
    client = client_connecting_over_tls("polling")

    client.init

    expect(connection.value).to eq(:a_handshake_the_client_ended)
    expect(client.ready?).to be(false)
  end
end
