# frozen_string_literal: true

require "json"
require "net/http"

module ConfigDirector
  module Internal
    module Connection
      module JsonPostRequest
        def self.to(uri, **body)
          request = Net::HTTP::Post.new(uri)
          request["Content-Type"] = "application/json"
          request["User-Agent"] = SdkIdentity.user_agent
          request.body = JSON.generate(body)
          request
        end
      end
    end
  end
end
