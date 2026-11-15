# frozen_string_literal: true

require "json"
require "net/http"

module ConfigDirector
  module Internal
    module Connection
      module JsonPostRequest
        def self.to(uri, sdk_identity, **body)
          request = Net::HTTP::Post.new(uri)
          request["Content-Type"] = "application/json"
          request["User-Agent"] = sdk_identity.user_agent
          request.body = JSON.generate(body)
          request
        end
      end
    end
  end
end
