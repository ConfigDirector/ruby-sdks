# frozen_string_literal: true

require "net/http"

module ConfigDirector
  module Internal
    module Connection
      module HttpSession
        def self.to(uri)
          http_session = Net::HTTP.new(uri.hostname.to_s, uri.port)
          http_session.use_ssl = uri.scheme == "https"
          http_session
        end
      end
    end
  end
end
