# frozen_string_literal: true

module Routing
  # Handles OpenRouteService API interactions for driving and walking legs.
  #
  # Responsibilities:
  # - Splitting waypoints into contiguous non-transit legs by profile
  # - Fetching geometry, segments, and surface data from ORS for each leg
  # - Fetching and persisting elevation data
  #
  # Merge and persist is handled by Routing::MergeService, which combines
  # LegResult objects from multiple routing backends (ORS, GoogleMapsService).
  #
  # @example
  #   legs = Routing::OrsService.new(route).fetch_legs
  #   Routing::MergeService.new(route, legs).call
  #
  class OrsService
    ELEVATION_POINT_LIMIT = 1999

    def initialize(route)
      @route = route
    end

    # Fetches all non-transit legs from ORS.
    #
    # @return [Array<LegResult>]
    def fetch_legs
      waypoint_legs.map { |leg| fetch_single_leg(leg[:profile], leg[:coordinates]) }
    end

    # Fetches a single ORS leg for the given profile and coordinates.
    # Called directly by CalculateRouteJob when orchestrating mixed-profile routes.
    #
    # If ORS reports an unroutable coordinate, that coordinate is removed and
    # the request is retried automatically. Recurses until the request succeeds
    # or fewer than 2 coordinates remain (in which case an empty LegResult is
    # returned). Handles sequences of consecutive unroutable waypoints.
    #
    # @param profile     [String]  ORS profile e.g. 'driving-car', 'foot-hiking'
    # @param coordinates [Array]   [[lon, lat], ...]
    # @return [LegResult]
    def fetch_single_leg(profile, coordinates)
      Rails.logger.debug "[OrsService] Fetching #{profile} leg with #{coordinates.size} waypoints"

      response = client.post(
        "/openrouteservice/v2/directions/#{profile}/geojson",
        {
          elevation: true,
          extra_info: %w[tollways surface waycategory waytype],
          coordinates: coordinates
        }
      )

      feature = response[:features].first
      extras  = feature[:properties][:extras] || {}
      surface = extras[:surface] || {}

      LegResult.new(
        profile: profile,
        coordinates: feature[:geometry][:coordinates],
        segments: feature[:properties][:segments],
        surfaces_values: surface[:values] || []
      )
    rescue StandardError => e
      bad_index = unroutable_coordinate_index(e.message)

      raise unless bad_index && bad_index < coordinates.size

      bad_coord = coordinates[bad_index]
      Rails.logger.warn "[OrsService] Skipping unroutable coordinate #{bad_index} " \
                        "(#{bad_coord.join(', ')}) and retrying: #{e.message}"
      pruned = coordinates.dup.tap { |c| c.delete_at(bad_index) }

      if pruned.size < 2
        Rails.logger.warn '[OrsService] Too few coordinates remain after skipping unroutable points; returning empty leg'
        return LegResult.new(profile: profile, coordinates: [], segments: [], surfaces_values: [])
      end

      fetch_single_leg(profile, pruned)
    end

    # Fetches elevation data from ORS and writes it into the route geometry as
    # a 4D (XYZM) LineString. For routes exceeding ELEVATION_POINT_LIMIT points,
    # the coordinate array is sliced Ruby-side into chunks and fetched separately.
    #
    # After writing the elevation geometry, surface indices and segment way_points
    # are clamped to the actual stored point count, since the ORS elevation API
    # silently drops trailing points and the original indices become out of range.
    #
    # @return [void]
    def import_elevation
      sql = if @route.geom.num_points > ELEVATION_POINT_LIMIT
              elevation_sql_for_split_route
            else
              elevation_sql_for_full_route
            end

      Route.connection.exec_update(sql)

      # Read the true stored point count once — @route.geom is stale after the
      # raw SQL update above, and both clamping methods need the same value.
      max_idx = stored_geometry_max_idx
      clamp_surface_indices(max_idx)
      clamp_segment_way_points(max_idx)
    end

    private

    # Groups consecutive non-transit waypoint pairs into legs by profile.
    #
    # Transit waypoints are skipped entirely and act as chunk boundaries —
    # pairs on either side of a transit gap are not merged even if they share
    # the same profile.
    #
    # @return [Array<Hash>] each with :profile and :coordinates
    def waypoint_legs
      waypoints
        .each_cons(2)
        .chunk_while { |(_a1, b1), (_a2, b2)| !b1.transit? && !b2.transit? && b1.profile == b2.profile }
        .reject { |pairs| pairs.first[1].transit? }
        .map do |pairs|
          profile       = pairs.first[1].profile
          leg_waypoints = [pairs.first.first, *pairs.map(&:last)]
          {
            profile: profile,
            coordinates: leg_waypoints.map { |wp| [wp.lonlat.x, wp.lonlat.y] }
          }
        end
    end

    # -- Elevation ---------------------------------------------------------

    # Fetches elevation for the route geometry by slicing the coordinate array
    # into chunks of at most ELEVATION_POINT_LIMIT points and issuing one ORS
    # elevation request per chunk. Chunks overlap by 1 point so the linestring
    # remains contiguous when reassembled.
    #
    # This replaces the previous ST_Split approach, which was unreliable on
    # complex geometries and could itself trigger ORS node-limit errors.
    #
    # @return [Array] elevated coordinates
    def fetch_all_elevation_coords
      geojson = RGeo::GeoJSON.encode(@route.geom)
      all_coords = geojson['coordinates']

      chunks = all_coords.each_slice(ELEVATION_POINT_LIMIT).to_a
      chunks.each_cons(2) { |prev, curr| curr.unshift(prev.last) }

      elevated = []
      chunks.each do |chunk|
        # ORS elevation expects 2D input — strip the Z dimension
        two_d = chunk.map { |c| c.first(2) }
        geojson_2d = { 'type' => 'LineString', 'coordinates' => two_d }
        response = client.post('/openelevationservice/v0/line', { format_in: 'geojson', geometry: geojson_2d })
        result_coords = response[:geometry][:coordinates]
        Rails.logger.debug "[OrsService] Elevation chunk: #{result_coords.count} points"
        # Drop the overlapping junction point on all but the first chunk
        result_coords = result_coords[1..] unless elevated.empty?
        elevated.concat(result_coords)
      end

      elevated
    end

    def elevation_sql_for_full_route
      Route.sanitize_sql(
        [
          'UPDATE routes SET geom = ST_Force4D(ST_GeomFromGeoJSON(:geom)) WHERE id = :id',
          { id: @route.id, geom: fetch_elevation_geojson(@route.geom) }
        ]
      )
    end

    def elevation_sql_for_split_route
      elevated_coords = fetch_all_elevation_coords
      points_wkt = elevated_coords.map { |c| c.join(' ') }.join(', ')
      wkt = "LINESTRING Z (#{points_wkt})"

      Route.sanitize_sql(
        [
          'UPDATE routes SET geom = ST_Force4D(ST_GeomFromText(:geom, 4326))::geography WHERE id = :id',
          { id: @route.id, geom: wkt }
        ]
      )
    end

    def fetch_elevation_geojson(line)
      geojson = RGeo::GeoJSON.encode(line)
      geojson['coordinates'].each { |c| c.delete_at(2) }
      response = client.post('/openelevationservice/v0/line', { format_in: 'geojson', geometry: geojson })
      Rails.logger.debug "[OrsService] Elevation points: #{response[:geometry][:coordinates].count}"
      response[:geometry].to_json
    end

    # -- Post-elevation clamping -------------------------------------------

    # Returns the maximum valid geometry index from the DB after elevation import.
    # @route.geom is stale after the raw SQL update, so we query ST_NPoints fresh.
    #
    # @return [Integer]
    def stored_geometry_max_idx
      Route.where(id: @route.id).pick(Arel.sql('ST_NPoints(geom::geometry)')) - 1
    end

    # Clamps surface['values'] start/end indices to the stored geometry bounds.
    #
    # The ORS elevation API silently drops trailing points, so stored geom may
    # be shorter than the geometry against which surface indices were recorded.
    #
    # @param max_idx [Integer]
    # @return [void]
    def clamp_surface_indices(max_idx)
      return unless @route.surfaces&.key?('values')

      clamped_values = @route.surfaces['values'].map do |start_idx, end_idx, surface_code|
        [start_idx.clamp(0, max_idx), end_idx.clamp(0, max_idx), surface_code]
      end

      @route.update_columns(surfaces: @route.surfaces.merge('values' => clamped_values))
    end

    # Clamps segment step way_points indices to the stored geometry bounds.
    #
    # Same root cause as surface indices — way_points recorded against the
    # original ORS geometry become out of range after elevation import truncates
    # trailing points. Out-of-range indices cause nil coordinate lookups in
    # DirectionsPresenter, producing missing timestamps and wrong map positions.
    #
    # @param max_idx [Integer]
    # @return [void]
    def clamp_segment_way_points(max_idx)
      return unless @route.segments.present?

      clamped_segments = @route.segments.map do |seg|
        clamped_steps = seg['steps'].map do |step|
          step.merge('way_points' => step['way_points'].map { |idx| idx.clamp(0, max_idx) })
        end
        seg.merge('steps' => clamped_steps)
      end

      @route.update_columns(segments: clamped_segments)
    end

    # -- Helpers -----------------------------------------------------------

    # Parses the ORS error message to extract the 0-based coordinate index of
    # an unroutable point.
    #
    # Expected format: "Could not find routable point within a radius of X
    #                   meters of specified coordinate N: lon lat."
    #
    # @param message [String]
    # @return [Integer, nil]
    def unroutable_coordinate_index(message)
      match = message.match(/coordinate\s+(\d+):/i)
      match&.[](1)&.to_i
    end

    def waypoints
      @waypoints ||= @route.waypoints.to_a
    end

    def client
      @client ||= OpenRouteService.new
    end
  end
end
