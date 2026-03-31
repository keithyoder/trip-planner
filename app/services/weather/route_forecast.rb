# frozen_string_literal: true

# app/services/weather/route_forecast.rb
#
# Builds a time-sliced temperature forecast for a route by sampling each
# non-routing waypoint's HourlyTemperature diurnal curve at the waypoint's
# estimated arrival time.
#
# Arrival times are computed from the M dimension of the route's 4D XYZM
# geometry, which was stamped by Routing::DurationImporter. The same
# segment-index mapping used by DirectionsPresenter is replicated here so
# the two stay in sync.
#
# == Usage
#
#   forecast = Weather::RouteForecast.new(route)
#   forecast.entries  # => Array<Weather::RouteForecast::Entry>
#
# Each Entry responds to:
#   .waypoint      – Waypoint
#   .arrival_time  – Time (UTC) or nil if timing data is unavailable
#   .temperature   – Float (°C) or nil if weather data is unavailable
#
# The first entry is the departure waypoint; its arrival_time is the route
# start time (seconds-from-midnight, same anchor used by DirectionsPresenter).
#
module Weather
  class RouteForecast
    Entry = Data.define(:waypoint, :arrival_time, :temperature)

    attr_reader :route

    # @param route [Route]
    def initialize(route)
      @route = route
    end

    # @return [Array<Entry>]
    def entries
      @entries ||= build_entries
    end

    private

    def build_entries
      return [] unless @route.start_time && @route.geom.present?

      all_waypoints = @route.waypoints.to_a
      segments      = @route.segments || []
      coords        = @route.geom.coordinates

      arriving_seg_for = build_arriving_seg_for(all_waypoints)

      # Same anchor as DirectionsPresenter#build_arrival_time:
      # start_time may be a DB interval that exceeds 86_400 — modulo keeps it
      # within a single day.
      base = Time.at(@route.start_time % 86_400.0).utc

      all_waypoints.filter_map do |waypoint|
        next if waypoint.routing?

        incoming_idx     = arriving_seg_for[waypoint.sequence]
        incoming_segment = incoming_idx ? segments[incoming_idx] : nil

        arrival = compute_arrival(incoming_segment, coords, base)
        temp    = sample_temperature(waypoint, arrival)

        Entry.new(waypoint: waypoint, arrival_time: arrival, temperature: temp)
      end
    end

    # Replicates the arriving_seg_for mapping from DirectionsPresenter.
    # seg_idx is always incremented (routing waypoints are transparent
    # pass-throughs for ORS) but the index is only recorded for non-routing
    # destination waypoints.
    #
    # @param all_waypoints [Array<Waypoint>]
    # @return [Hash{Integer => Integer}] sequence → segment index
    def build_arriving_seg_for(all_waypoints)
      result  = {}
      seg_idx = 0
      all_waypoints.each_cons(2) do |_a, b|
        result[b.sequence] = seg_idx unless b.routing?
        seg_idx += 1
      end
      result
    end

    # @param segment [Hash, nil]  ORS segment; nil for the departure waypoint
    # @param coords  [Array]      route geometry coordinates
    # @param base    [Time]       route start anchor (UTC)
    # @return [Time, nil]
    def compute_arrival(segment, coords, base)
      # First (departure) waypoint — no incoming segment; use start time.
      return base unless segment

      last_wp_idx = segment['steps'].last&.dig('way_points', -1)
      return nil unless last_wp_idx && coords[last_wp_idx]&.[](3)

      base + coords[last_wp_idx][3]
    end

    # Samples the waypoint's diurnal curve at the arrival hour.
    # The hour is taken from the UTC Time object, which uses the same
    # midnight anchor as start_time — consistent with DirectionsPresenter.
    #
    # @param waypoint     [Waypoint]
    # @param arrival_time [Time, nil]
    # @return [Float, nil] temperature in °C
    def sample_temperature(waypoint, arrival_time)
      return nil unless arrival_time

      waypoint.hourly_temperature_curve&.at(arrival_time.hour)
    end
  end
end
