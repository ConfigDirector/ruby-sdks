# frozen_string_literal: true

require "net/http"

module ConfigDirector
  module Internal
    module Connection
      module HttpSession
        def self.to(uri)
          Net::HTTP.new(uri.hostname.to_s, uri.port).tap { |http_session| http_session.use_ssl = uri.scheme == "https" }
        end
      end
    end
  end
end
