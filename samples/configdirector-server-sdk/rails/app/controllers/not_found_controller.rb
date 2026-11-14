# frozen_string_literal: true

class NotFoundController < ApplicationController
  def show
    render json: { error: "Not found. Try GET /configs" }, status: :not_found
  end
end
