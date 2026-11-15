# frozen_string_literal: true

require_relative "client_of_the_scripted_sdk_server"

module SampleConfigs
  extend WirePayloads

  ENVIRONMENT_ID = WirePayloads::ENVIRONMENT_ID

  def self.wire_config(key, id:, type:, default_value:, default_value_id:, default_variation_id: nil, rules: [],
                       variations: [])
    {
      "id" => id, "key" => key, "type" => type, "typeConstraints" => nil, "variations" => variations,
      "target" => {
        "environmentId" => ENVIRONMENT_ID, "rules" => rules, "defaultValue" => default_value,
        "defaultValueId" => default_value_id, "defaultVariationId" => default_variation_id
      }.compact
    }
  end

  WIRE_CONFIGS = [
    wire_config(
      "temporary-feature-flag",
      id: "7b0c4f52-3d1e-4a86-9c2f-1e5d8a6b4c01", type: "boolean", default_value: "false",
      default_value_id: "value-flag-off", default_variation_id: "variation-flag-off",
      rules: [{
        "id" => "rule-flag-rollout", "order" => 0, "type" => "percentage", "target" => "percentage",
        "conditions" => [],
        "percentages" => [{
          "id" => "share-flag-on", "percentage" => 100, "value" => "true", "valueId" => "value-flag-on",
          "variationId" => "variation-flag-on"
        }]
      }],
      variations: [
        { "id" => "variation-flag-on", "name" => "On", "value" => "true" },
        { "id" => "variation-flag-off", "name" => "Off", "value" => "false" }
      ]
    ),
    wire_config(
      "permanent-kill-switch",
      id: "2f6d1c3e-8a47-4b55-9d0e-6c1f7a9b2e02", type: "boolean", default_value: "true",
      default_value_id: "value-kill-switch-on"
    ),
    wire_config(
      "integer-config",
      id: "9a3e5b71-6c2d-4f08-8b1a-4d7c2e9f5a03", type: "integer", default_value: "42",
      default_value_id: "value-integer-42",
      rules: [{
        "id" => "rule-beta-app", "order" => 0, "type" => "conditional", "target" => "value", "value" => "7",
        "valueId" => "value-integer-7", "percentages" => [],
        "conditions" => [{
          "id" => "condition-beta-app", "kind" => "attribute", "attribute" => "appName", "operator" => "equals",
          "targetType" => "text", "targetValues" => ["beta-app"]
        }]
      }]
    ),
    wire_config(
      "day-of-the-week-config",
      id: "5c8a2d94-1b7f-4e63-a0d5-9f3b6c1e7d04", type: "string", default_value: "Monday",
      default_value_id: "value-monday",
      rules: [{
        "id" => "rule-pro-plan", "order" => 0, "type" => "conditional", "target" => "value", "value" => "Tuesday",
        "valueId" => "value-tuesday", "percentages" => [],
        "conditions" => [{
          "id" => "condition-pro-plan", "kind" => "attribute", "attribute" => "traits", "trait" => "/plan",
          "operator" => "equals", "targetType" => "text", "targetValues" => ["pro"]
        }]
      }]
    ),
    wire_config(
      "json-value-config",
      id: "e1d7f3a6-4c9b-4d21-b8e0-2a6f5c3d9b05", type: "json",
      default_value: '{"greeting":"hello","sizes":[1,2]}', default_value_id: "value-json-greeting"
    ),
    wire_config(
      "json-list-config",
      id: "0a4c9e27-5d83-4f16-b7a2-6e1d3c8f9b09", type: "json", default_value: '["small","large"]',
      default_value_id: "value-json-sizes"
    ),
    wire_config(
      "float-config",
      id: "4b9e6c18-7f3a-4c52-9e1d-8c0a7b2f6e06", type: "float", default_value: "26.0",
      default_value_id: "value-float-26"
    ),
    wire_config(
      "config-without-a-value",
      id: "c6a1e8d3-2b5f-4937-a4c8-3e9d1f7b0a07", type: "string", default_value: "",
      default_value_id: "value-without-text"
    ),
    wire_config(
      "malformed-json-config",
      id: "8d2f7a45-9e6c-4b10-8f3e-5b1c4d6a2e08", type: "json", default_value: '{"greeting":',
      default_value_id: "value-malformed-json"
    )
  ].freeze

  PAYLOAD_TEXT = full_payload_text(configs: WIRE_CONFIGS)
end

RSpec.shared_context "with an SDK server that serves the sample configs" do
  include_context "with a client of the scripted SDK server"

  let!(:thread_answering_every_stream_request) do
    server_started_on_this_thread = sdk_server
    Thread.new do
      loop do
        stream_request = server_started_on_this_thread.request_to(ScriptedSdkServer::STREAM_PATH, within: nil)
        stream_request.open_event_stream
        stream_request.send_event(SampleConfigs::PAYLOAD_TEXT)
      end
    end
  end

  after { thread_answering_every_stream_request.kill.join }

  def client_of_the_sample_configs(**client_options)
    client = ConfigDirector.create_client(
      "server-sdk-key", connection: ConfigDirector::ConnectionOptions.new(url: sdk_server.url), **client_options
    )
    clients_created << client
    client
  end
end
