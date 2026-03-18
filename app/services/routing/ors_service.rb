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
    # @param profile     [String]  ORS profile e.g. 'driving-car', 'foot-hiking'
    # @param coordinates [Array]   [[lon, lat], ...]
    # @return [LegResult]
    def fetch_single_leg(profile, coordinates)
      Rails.logger.debug "[OrsService] Fetching #{profile} leg with #{coordinates.size} waypoints"

      response = client.post(
        "/v2/directions/#{profile}/geojson",
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
    end

    # Fetches elevation data from ORS and writes it into the route geometry as
    # a 4D (XYZM) LineString. For routes exceeding ELEVATION_POINT_LIMIT points,
    # the coordinate array is sliced Ruby-side into chunks and fetched separately.
    #
    # @return [void]
    def import_elevation
      sql = if @route.geom.num_points > ELEVATION_POINT_LIMIT
              elevation_sql_for_split_route
            else
              elevation_sql_for_full_route
            end

      Route.connection.exec_update(sql)
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
    # @return [String] WKT LINESTRING (lon lat ele, ...) suitable for ST_GeomFromText
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
        response = client.post('/elevation/line', { format_in: 'geojson', geometry: geojson_2d })
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
      response = client.post('/elevation/line', { format_in: 'geojson', geometry: geojson })
      Rails.logger.debug "[OrsService] Elevation points: #{response[:geometry][:coordinates].count}"
      response[:geometry].to_json
    end

    # -- Helpers -----------------------------------------------------------

    def waypoints
      @waypoints ||= @route.waypoints.to_a
    end

    def client
      @client ||= OpenRouteService.new
    end
  end
end
