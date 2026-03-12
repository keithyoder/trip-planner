# frozen_string_literal: true

module Routing
  # Fetches transit directions from the Google Maps Directions API for a single
  # waypoint pair and returns a LegResult compatible with MergeService.
  #
  # Responsibilities:
  # - Calling the Directions API with mode=transit and a real departure time
  #   derived from the route's start_time and the trip's start_on date
  # - Decoding per-step polylines and concatenating them into a single
  #   coordinate array in [lon, lat] order with linearly interpolated
  #   elapsed-second M values
  # - Building ORS-style steps: one per transit/walking sub-leg with
  #   instruction, distance, duration, and way_points index pair
  #
  # The resulting LegResult slots directly into MergeService alongside ORS legs.
  #
  # @example
  #   leg = Routing::GoogleMapsService.new(route, waypoint_a, waypoint_b).fetch_leg
  #
  class GoogleMapsService
    BASE_URL = 'https://maps.googleapis.com/maps/api/directions/json'

    def initialize(route, origin, destination)
      @route       = route
      @origin      = origin
      @destination = destination
    end

    # Fetches transit directions and returns a LegResult.
    #
    # Surface values are set from the dominant vehicle type across all transit
    # steps — :rail for train/metro/tram, :bus for bus/trolleybus.
    # A single surface entry covers the full coordinate range of the leg.
    #
    # @return [LegResult]
    def fetch_leg
      response = fetch_directions
      leg      = response[:legs].first

      coordinates = []
      steps       = []
      # Track [start_idx, end_idx, surface_code] per transit step
      step_surfaces = []

      leg[:steps].each do |step|
        step_coords  = decode_polyline(step[:polyline][:points])
        step_seconds = step[:duration][:value].to_f
        instruction  = build_instruction(step)

        coord_start_idx = coordinates.empty? ? 0 : coordinates.size - 1
        elapsed_start   = coordinates.empty? ? 0.0 : coordinates.last[3]

        # Deduplicate: skip first point of subsequent steps (shared junction)
        incoming = coordinates.empty? ? step_coords : step_coords[1..]

        # Linearly interpolate elapsed seconds across this step's coordinates
        point_count = incoming.size
        incoming.each_with_index do |(lon, lat), i|
          fraction = point_count > 1 ? i.to_f / (point_count - 1) : 1.0
          elapsed  = elapsed_start + (fraction * step_seconds)
          coordinates << [lon, lat, 0, elapsed.round]
        end

        coord_end_idx = coordinates.size - 1

        steps << {
          instruction: instruction,
          distance: step[:distance][:value].to_f,
          duration: step_seconds,
          way_points: [coord_start_idx, coord_end_idx]
        }

        # Record surface for transit steps only (not walking transfer steps)
        if step[:travel_mode] == 'TRANSIT'
          surface_code = transit_surface_code(step)
          step_surfaces << [coord_start_idx, coord_end_idx, surface_code]
        end
      end

      LegResult.new(
        profile: 'transit',
        coordinates: coordinates,
        segments: [{ steps: steps, distance: leg_distance(leg), duration: leg_duration(leg) }],
        surfaces_values: step_surfaces
      )
    end

    private

    # Calls the Google Maps Directions API.
    #
    # departure_time is built from trip.start_on + route.start_time so that
    # real timetables are fetched for the planned travel day and time.
    #
    # @return [Hash] the first route from the API response (symbolized keys)
    def fetch_directions
      ts = departure_unix_timestamp
      params = {
        origin: "#{@origin.lonlat.y},#{@origin.lonlat.x}",
        destination: "#{@destination.lonlat.y},#{@destination.lonlat.x}",
        mode: 'transit',
        departure_time: ts,
        key: api_key
      }

      uri       = URI(BASE_URL)
      uri.query = URI.encode_www_form(params)

      Rails.logger.debug "[GoogleMapsService] Request URL (no key): #{BASE_URL}?origin=#{params[:origin]}&destination=#{params[:destination]}&mode=transit&departure_time=#{ts}"
      Rails.logger.debug "[GoogleMapsService] departure_time: #{ts} (#{Time.zone.at(ts)})"
      Rails.logger.debug "[GoogleMapsService] trip.start_on: #{@route.trip.start_on}, route.start_time: #{@route.start_time.inspect}"

      response = Net::HTTP.get_response(uri)
      raise "Google Maps API error: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      body   = JSON.parse(response.body, symbolize_names: true)
      status = body[:status]

      Rails.logger.debug "[GoogleMapsService] Response status: #{status}"
      Rails.logger.debug "[GoogleMapsService] Full response: #{body.except(:routes).inspect}"

      raise "Google Maps Directions failed: #{status} — #{body[:error_message]}" unless status == 'OK'

      Rails.logger.debug "[GoogleMapsService] #{@origin.name} → #{@destination.name}: #{body[:routes].first[:legs].first[:steps].size} steps"

      body[:routes].first
    end

    # Builds a Unix timestamp from the trip's start_on date and the route's
    # start_time interval (seconds from midnight).
    #
    # @return [Integer] Unix timestamp
    def departure_unix_timestamp
      tomorrow    = Date.tomorrow
      time_of_day = @route.start_time.to_i % 86_400
      Time.zone.local(tomorrow.year, tomorrow.month, tomorrow.day).to_i + time_of_day
    end

    # Builds a human-readable instruction for a Google Maps step.
    #
    # Transit steps include the line name and headsign; walking steps use the
    # HTML-stripped maneuver summary.
    #
    # @param step [Hash] a step from the Directions API response
    # @return [String]
    def build_instruction(step)
      if step[:travel_mode] == 'TRANSIT'
        details   = step[:transit_details]
        line      = details[:line]
        line_name = line[:short_name] || line[:name]
        departure = details[:departure_stop][:name]
        arrival   = details[:arrival_stop][:name]
        headsign  = details[:headsign]
        num_stops = details[:num_stops]

        "Board #{line_name} (#{headsign}) at #{departure} · #{num_stops} stop#{num_stops == 1 ? '' : 's'} · Alight at #{arrival}"
      else
        # Walking transfer leg — strip HTML tags from Google's instruction
        ActionView::Base.full_sanitizer.sanitize(step[:html_instructions])
      end
    end

    # Decodes a Google Maps encoded polyline string into [[lon, lat], ...].
    # Google returns lat/lng — we swap to [lon, lat] for consistency with ORS.
    #
    # @param encoded [String]
    # @return [Array<Array<Float>>]
    def decode_polyline(encoded)
      points  = []
      index   = 0
      lat     = 0
      lng     = 0

      while index < encoded.length
        shift  = 0
        result = 0

        loop do
          byte    = encoded[index].ord - 63
          index  += 1
          result |= (byte & 0x1f) << shift
          shift  += 5
          break if byte < 0x20
        end

        dlat = result.odd? ? ~(result >> 1) : result >> 1
        lat += dlat

        shift  = 0
        result = 0

        loop do
          byte    = encoded[index].ord - 63
          index  += 1
          result |= (byte & 0x1f) << shift
          shift  += 5
          break if byte < 0x20
        end

        dlng = result.odd? ? ~(result >> 1) : result >> 1
        lng += dlng

        points << [(lng / 1e5).round(6), (lat / 1e5).round(6)]
      end

      points
    end

    # Maps a Google Maps transit step to a SurfaceProfile surface code.
    # Rail types (train, metro, tram, etc.) map to :rail.
    # Everything else (bus, trolleybus, etc.) maps to :bus.
    #
    # @param step [Hash] a TRANSIT travel_mode step
    # @return [Integer] surface code from Routes::SurfaceProfile::SURFACE_TYPES
    def transit_surface_code(step)
      vehicle_type = step.dig(:transit_details, :line, :vehicle, :type).to_s
      if RAIL_VEHICLE_TYPES.include?(vehicle_type)
        Routes::SurfaceProfile::SURFACE_TYPES[:rail]
      else
        Routes::SurfaceProfile::SURFACE_TYPES[:bus]
      end
    end

    RAIL_VEHICLE_TYPES = %w[
      RAIL
      METRO_RAIL
      SUBWAY
      TRAM
      MONORAIL
      HEAVY_RAIL
      COMMUTER_TRAIN
      HIGH_SPEED_TRAIN
    ].freeze

    def leg_distance(leg)
      leg[:steps].sum { |s| s[:distance][:value].to_f }
    end

    def leg_duration(leg)
      leg[:steps].sum { |s| s[:duration][:value].to_f }
    end

    def api_key
      ENV['GOOGLE_MAPS_API_KEY'] || raise('GOOGLE_MAPS_API_KEY environment variable not set')
    end
  end
end
