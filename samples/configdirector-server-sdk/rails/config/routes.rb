# frozen_string_literal: true

Rails.application.routes.draw do
  get "configs", to: "configs#index", format: false
  match "(*path)", to: "not_found#show", via: :all
end
