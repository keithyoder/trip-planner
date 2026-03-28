# frozen_string_literal: true

class CalculateRouteJob < ApplicationJob
  queue_as :default

  def perform(route_id)
    route = Route.find(route_id)
    return unless route

    legs = fetch_legs(route)
    Routing::MergeService.new(route, legs).call
    sleep(2)
    route.reload

    # --- TEMP DEBUG ---
    Rails.logger.debug '[DEBUG] Waypoints:'
    route.waypoints.each_with_index do |wp, i|
      Rails.logger.debug "  [#{i}] #{wp.name} profile=#{wp.profile} routing=#{wp.routing?} coords=#{wp.lonlat.x.round(5)},#{wp.lonlat.y.round(5)}"
    end
    Rails.logger.debug "[DEBUG] Segments (#{route.segments.size}):"
    route.segments.each_with_index do |seg, i|
      Rails.logger.debug "  [#{i}] duration=#{seg['duration']} distance=#{seg['distance']} steps=#{seg['steps'].size}"
      seg['steps'].each_with_index do |step, j|
        Rails.logger.debug "    step[#{j}] way_points=#{step['way_points']} distance=#{step['distance']}"
      end
    end
    Rails.logger.debug "[DEBUG] Surfaces values: #{route.surfaces['values'].inspect}"
    Rails.logger.debug "[DEBUG] Geom points: #{route.geom.num_points}"
    # --- END TEMP DEBUG ---

    Routing::OrsService.new(route).import_elevation
    route.reload
    Routing::DurationImporter.new(route).import

    CalculateFuelJob.perform_later(route.trip_id)
  end

  private

  # Fetches all legs for the route, dispatching to the appropriate service
  # based on profile. ORS handles driving and walking legs; GoogleMapsService
  # handles transit legs. Results are returned in waypoint sequence order
  # ready for MergeService to combine.
  #
  # @param route [Route]
  # @return [Array<Routing::LegResult>]
  def fetch_legs(route)
    waypoints = route.waypoints.to_a
    has_transit = waypoints.any?(&:transit?)

    if has_transit
      fetch_mixed_legs(route, waypoints)
    else
      Routing::OrsService.new(route).fetch_legs
    end
  end

  # Fetches legs for routes with mixed profiles (transit + walking/driving).
  # Processes waypoint pairs in sequence, grouping contiguous non-transit
  # pairs for ORS and transit pairs for GoogleMapsService.
  #
  # Each contiguous non-transit run is sent to ORS as a single multi-waypoint
  # leg. Each transit pair is sent to GoogleMapsService individually.
  # Results are interleaved in the correct sequence order.
  #
  # @param route     [Route]
  # @param waypoints [Array<Waypoint>]
  # @return [Array<Routing::LegResult>]
  def fetch_mixed_legs(route, waypoints)
    legs = []

    # Split pairs into runs: contiguous non-transit runs and individual transit pairs.
    pairs = waypoints.each_cons(2).to_a

    pairs
      .chunk_while { |(_a1, b1), (_a2, b2)| b1.transit? == b2.transit? && b1.profile == b2.profile }
      .each do |run|
        if run.first[1].transit?
          # Each transit pair becomes one GoogleMaps leg
          run.each do |(a, b)|
            Rails.logger.debug "[CalculateRouteJob] Fetching transit leg: #{a.name} → #{b.name}"
            legs << Routing::GoogleMapsService.new(route, a, b).fetch_leg
          end
        else
          # Contiguous non-transit run becomes one ORS leg request
          profile       = run.first[1].profile
          leg_waypoints = [run.first.first, *run.map(&:last)]
          coordinates   = leg_waypoints.map { |wp| [wp.lonlat.x, wp.lonlat.y] }

          Rails.logger.debug "[CalculateRouteJob] Fetching #{profile} leg with #{coordinates.size} waypoints"
          legs << Routing::OrsService.new(route).fetch_single_leg(profile, coordinates)
        end
      end

    legs
  end
end
