# frozen_string_literal: true

require "openssl"

class SelfSignedCertificate
  attr_reader :key, :certificate

  def initialize
    @key = OpenSSL::PKey::RSA.new(2048)
    @certificate = certificate_for_the_loopback_address
    @certificate.public_key = @key.public_key
    extensions = OpenSSL::X509::ExtensionFactory.new(@certificate, @certificate)
    @certificate.add_extension(extensions.create_extension("subjectAltName", "IP:127.0.0.1"))
    @certificate.add_extension(extensions.create_extension("basicConstraints", "CA:TRUE", true))
    @certificate.sign(@key, OpenSSL::Digest.new("SHA256"))
  end

  def write_into(folder)
    certificate_path = File.join(folder, "certificate.pem")
    key_path = File.join(folder, "key.pem")
    File.write(certificate_path, @certificate.to_pem)
    File.write(key_path, @key.to_pem)

    [certificate_path, key_path]
  end

  private

  def certificate_for_the_loopback_address
    OpenSSL::X509::Certificate.new.tap do |certificate|
      certificate.version = 2
      certificate.serial = 1
      certificate.subject = certificate.issuer = OpenSSL::X509::Name.parse("/CN=127.0.0.1")
      certificate.not_before = Time.now - 60
      certificate.not_after = Time.now + 3600
    end
  end
end
