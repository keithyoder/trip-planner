# frozen_string_literal: true

json.extract! trip, :id, :name, :start_on, :created_at, :updated_at
json.url trip_url(trip, format: :json)
