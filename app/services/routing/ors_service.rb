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
    # a 4D (XYZM) LineString. Splits the geometry into two halves first when
    # the route exceeds the ORS point limit.
    #
    # @return [void]
    def import_elevation
      sql = if @route.geom.num_points > ELEVATION_POINT_LIMIT
              elevation_sql_for_split_route
            else
              elevation_sql_for_full_route
            end

      Route.connection.exec_update(sql)

      stored_count = Route.connection.exec_query(
        Route.sanitize_sql(
          ['SELECT ST_NPoints(geom::geometry) AS n FROM routes WHERE id = :id', { id: @route.id }]
        )
      ).first['n'].to_i

      expected_count = @route.geom.num_points
      return if stored_count >= expected_count

      Rails.logger.debug "[OrsService] Elevation import dropped #{expected_count - stored_count} points for route #{@route.id}, clamping segments and surfaces"

      max_idx = stored_count - 1

      clamped_segments = @route.segments.map do |seg|
        clamped_steps = seg['steps'].map do |step|
          step.merge('way_points' => step['way_points'].map { |idx| [idx, max_idx].min })
        end
        seg.merge('steps' => clamped_steps)
      end

      clamped_surfaces = @route.surfaces.merge(
        'values' => @route.surfaces['values'].map do |start_idx, end_idx, code|
          [[start_idx, max_idx].min, [end_idx, max_idx].min, code]
        end
      )

      @route.update!(segments: clamped_segments, surfaces: clamped_surfaces)
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

    def elevation_sql_for_full_route
      Route.sanitize_sql(
        [
          'UPDATE routes SET geom = ST_Force4D(ST_GeomFromGeoJSON(:geom)) WHERE id = :id',
          { id: @route.id, geom: fetch_elevation_geojson(@route.geom) }
        ]
      )
    end

    def elevation_sql_for_split_route
      Route.sanitize_sql(
        [
          <<~SQL,
            UPDATE routes
            SET geom = ST_Force4D(ST_MakeLine(
              ST_GeomFromGeoJSON(:geom1),
              ST_GeomFromGeoJSON(:geom2)
            ))
            WHERE id = :id
          SQL
          {
            id: @route.id,
            geom1: fetch_elevation_geojson(subsegment(1)),
            geom2: fetch_elevation_geojson(subsegment(2))
          }
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

    def subsegment(segment)
      sql = Arel.sql(
        Route.sanitize_sql(
          [
            <<~SQL, segment
              ST_GeometryN(
                ST_Split(
                  geom::geometry,
                  ST_GeometryN(ST_Points(geom::geometry), ST_NPoints(geom::geometry)/2)
                ), ?
              )::geography AS geom
            SQL
          ]
        )
      )
      @route.trip.routes.where(id: @route.id).pluck(sql).first
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
