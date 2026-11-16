# frozen_string_literal: true

require "openssl"
require "socket"
require_relative "self_signed_certificate"

class SelfSignedTlsListener
  def initialize
    self_signed = SelfSignedCertificate.new
    tls_context = OpenSSL::SSL::SSLContext.new
    tls_context.cert = self_signed.certificate
    tls_context.key = self_signed.key
    @listener = TCPServer.new("127.0.0.1", 0)
    @tls_server = OpenSSL::SSL::SSLServer.new(@listener, tls_context)
  end

  def url
    "https://127.0.0.1:#{@listener.addr[1]}"
  end

  def what_the_next_connection_brings
    Thread.new do
      @tls_server.accept.gets.nil? ? :no_request : :a_request
    rescue OpenSSL::SSL::SSLError, SystemCallError, EOFError
      :a_handshake_the_client_ended
    end
  end

  def close
    @listener.close
  end
end
