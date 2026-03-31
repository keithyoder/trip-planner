# frozen_string_literal: true

# Fetches weather for a single waypoint and broadcasts Turbo Stream updates.
#
# Always updates the waypoint show view partials.
#
# If +route_id+ is supplied, also re-renders and broadcasts the route weather
# forecast table. Waypoints on that route which still lack a fresh
# WeatherEstimate have nil memoized on them so the broadcast render does not
# trigger additional API calls — they will appear as "—" until their own jobs
# complete.
class FetchWaypointWeatherJob < ApplicationJob
  queue_as :default

  retry_on ::Weather::Client::Error, wait: :polynomially_longer, attempts: 3

  def perform(waypoint_id, route_id: nil)
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

    broadcast_route_forecast(route_id) if route_id
  end

  private

  # Re-renders the route weather forecast table and broadcasts it.
  # Waypoints without a fresh DB estimate have nil memoized so the render
  # does not trigger extra API calls; they will show "—" until their jobs run.
  def broadcast_route_forecast(route_id)
    route = Route.includes(:route_sequence, :waypoint_start, :waypoint_end, :trip)
                 .find(route_id)

    route.waypoints.reject(&:routing?).each do |wp|
      next unless wp.lonlat && wp.planned_date

      estimate = WeatherEstimate.for_location(
        wp.lonlat.y.to_f.round(2),
        wp.lonlat.x.to_f.round(2),
        wp.planned_date
      )

      wp.instance_variable_set(:@weather, nil) unless estimate&.fresh?
    end

    Turbo::StreamsChannel.broadcast_replace_to(
      "route_#{route_id}_weather_forecast",
      target: "route-#{route_id}-directions-weather",
      partial: "routes/directions",
      locals: { route: route, trip: route.trip, weather_pending: false }
    )
  end
end
