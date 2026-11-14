# frozen_string_literal: true

class ConfigsController < ApplicationController
  CONTEXT_PARAMETERS = %w[id kind name anonymous].freeze

  def index
    client = ConfigDirectorClientPerProcess.client
    context = context_from_query
    render json: {
      "temporary-feature-flag" => client.get_value("temporary-feature-flag", true, context),
      "permanent-kill-switch" => client.get_value("permanent-kill-switch", false, context),
      "integer-config" => client.get_value("integer-config", 10, context),
      "day-of-the-week-config" => client.get_value("day-of-the-week-config", "Friday", context),
      "json-value-config" => client.get_value("json-value-config", {}, context)
    }
  end

  private

  def context_from_query
    query = request.query_parameters
    ConfigDirector::Context.new(
      id: query["id"], kind: query["kind"], name: query["name"],
      traits: query.except(*CONTEXT_PARAMETERS).presence, anonymous: query["anonymous"] == "true"
    )
  end
end
