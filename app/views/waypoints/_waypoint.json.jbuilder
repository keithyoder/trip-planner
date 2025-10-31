# frozen_string_literal: true

json.extract! waypoint, :id, :name, :sequence, :created_at, :updated_at
json.url waypoint_url(waypoint, format: :json)
