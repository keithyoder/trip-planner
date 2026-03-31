# frozen_string_literal: true

# Fetches weather for a single waypoint and broadcasts a Turbo Stream update
# to the waypoint show view once data is available.
class FetchWaypointWeatherJob < ApplicationJob
  queue_as :default

  retry_on ::Weather::Client::Error, wait: :polynomially_longer, attempts: 3

  def perform(waypoint_id)
    waypoint = Waypoint.find(waypoint_id)

    # Fetch and cache (fetch_weather writes through to WeatherEstimate)
    waypoint.weather

    Turbo::StreamsChannel.broadcast_replace_to(
      "waypoint_#{waypoint_id}_weather",
      target: "waypoint-#{waypoint_id}-weather",
      partial: "waypoints/weather",
      locals: { waypoint: waypoint }
    )

    Turbo::StreamsChannel.broadcast_replace_to(
      "waypoint_#{waypoint_id}_weather",
      target: "waypoint-#{waypoint_id}-weather-chart",
      partial: "waypoints/weather_hourly_chart",
      locals: { waypoint: waypoint }
    )
  end
end
