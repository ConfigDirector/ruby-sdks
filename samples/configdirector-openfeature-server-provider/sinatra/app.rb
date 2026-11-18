# frozen_string_literal: true

require "json"
require "sinatra/base"
require "configdirector/openfeature"
require_relative "lib/open_feature_client_per_process"

class SinatraSample < Sinatra::Base
  CONTEXT_PARAMETERS = %w[id name anonymous].freeze
  private_constant :CONTEXT_PARAMETERS

  get "/configs" do
    client = OpenFeatureClientPerProcess.client
    context = evaluation_context_from_query
    json(
      "temporary-feature-flag" => client.fetch_boolean_value(
        flag_key: "temporary-feature-flag", default_value: true, evaluation_context: context
      ),
      "permanent-kill-switch" => client.fetch_boolean_value(
        flag_key: "permanent-kill-switch", default_value: false, evaluation_context: context
      ),
      "integer-config" => client.fetch_integer_value(
        flag_key: "integer-config", default_value: 10, evaluation_context: context
      ),
      "day-of-the-week-config" => client.fetch_string_value(
        flag_key: "day-of-the-week-config", default_value: "Friday", evaluation_context: context
      ),
      "json-value-config" => client.fetch_object_value(
        flag_key: "json-value-config", default_value: {}, evaluation_context: context
      )
    )
  end

  get "/configs/:key" do |key|
    details = OpenFeatureClientPerProcess.client.fetch_boolean_details(
      flag_key: key, default_value: false, evaluation_context: evaluation_context_from_query
    )
    json(
      value: details.value, variant: details.variant, reason: details.reason,
      error_code: details.error_code, error_message: details.error_message
    )
  end

  not_found do
    json(error: "Not found. Try GET /configs")
  end

  private

  def evaluation_context_from_query
    query = request.GET
    OpenFeature::SDK::EvaluationContext.new(
      targeting_key: query["id"], name: query["name"], anonymous: query["anonymous"] == "true",
      traits: query.except(*CONTEXT_PARAMETERS)
    )
  end

  def json(body)
    content_type :json
    JSON.generate(body)
  end
end
