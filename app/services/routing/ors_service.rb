# frozen_string_literal: true

module Routing
  # Handles all OpenRouteService API interactions for a route.
  #
  # Responsibilities:
  # - Fetching directions (geometry, segments, surfaces) from ORS
  # - Fetching elevation data and stitching it back into the route geometry
  # - Persisting results directly to the routes table via raw SQL
  #
  # The service owns the ORS token and knows nothing about associations
  # beyond what it receives as arguments. Route#calculate_route and
  # Route#import_elevation become one-liners that delegate here.
  #
  # @example
  #   Routes::OrsService.new(route).calculate
  #   Routes::OrsService.new(route).import_elevation
  #
  class OrsService
    # ORS supports a maximum of 2000 coordinate points per elevation request.
    ELEVATION_POINT_LIMIT = 1999

    # @param route [Route] the route record to operate on
    def initialize(route)
      @route = route
    end

    # Fetches directions from ORS and persists geometry, segments, and surfaces.
    #
    # Hits POST /v2/directions/{profile}/geojson with elevation and extra info,
    # then writes the 4D geometry, segments JSON, and surfaces JSON back to the
    # routes table in a single pass.
    #
    # @return [void]
    def calculate
      response = fetch_directions
      persist_directions(response)
    end

    # Fetches elevation data from ORS and writes it into the route geometry as
    # a 4D (XYZM) LineString. Splits the geometry into two halves first when the
    # route exceeds the ORS point limit.
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

    # -- Directions --------------------------------------------------------

    def fetch_directions
      client.post(
        "/v2/directions/#{@route.profile}/geojson",
        {
          elevation: true,
          extra_info: %w[tollways surface waycategory waytype],
          coordinates: waypoints_coordinates
        }
      )
    end

    def persist_directions(response)
      feature = response[:features].first

      @route.update!(
        segments: feature[:properties][:segments],
        surfaces: feature[:properties][:extras][:surface]
      )

      Route.connection.exec_update(
        Route.sanitize_sql(
          [
            'UPDATE routes SET geom = ST_Force4D(ST_GeomFromGeoJSON(:geom)) WHERE id = :id AND trip_id = :trip_id',
            {
              id: @route.id,
              trip_id: @route.trip_id,
              geom: feature[:geometry].to_json
            }
          ]
        )
      )
    end

    # -- Elevation ---------------------------------------------------------

    # Builds SQL for routes within the ORS point limit (single request).
    def elevation_sql_for_full_route
      Route.sanitize_sql(
        [
          'UPDATE routes SET geom = ST_Force4D(ST_GeomFromGeoJSON(:geom)) WHERE id = :id',
          { id: @route.id, geom: fetch_elevation_geojson(@route.geom) }
        ]
      )
    end

    # Builds SQL for long routes that must be split into two halves before
    # being sent to ORS, then re-joined with ST_MakeLine.
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

    # Calls the ORS elevation API for a single geometry and returns the
    # enriched geometry as a JSON string ready for ST_GeomFromGeoJSON.
    #
    # @param line [RGeo::Geography] the geometry to enrich
    # @return [String] GeoJSON geometry string
    def fetch_elevation_geojson(line)
      geojson = RGeo::GeoJSON.encode(line)
      # ORS elevation endpoint does not accept the M value - strip it
      geojson['coordinates'].each { |c| c.delete_at(2) }

      response = client.post('/elevation/line', { format_in: 'geojson', geometry: geojson })
      Rails.logger.debug "[OrsService] Elevation points: #{response[:geometry][:coordinates].count}"

      response[:geometry].to_json
    end

    # Extracts one half of the route geometry via PostGIS.
    # ST_Split divides the linestring at its midpoint; ST_GeometryN picks
    # the requested segment (1 = first half, 2 = second half).
    #
    # @param segment [Integer] 1 or 2
    # @return [RGeo::Geography]
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

    def waypoints_coordinates
      @route.waypoints.map { |wp| [wp.lonlat.x, wp.lonlat.y] }
    end

    def client
      @client ||= OpenRouteService.new
    end
  end
end
