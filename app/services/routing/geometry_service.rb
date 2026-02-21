# frozen_string_literal: true

module Routing
  # Provides spatial queries against a route's geometry.
  #
  # Extracted from Route to keep PostGIS-heavy SQL out of the model. The model
  # delegates #points, #boundaries, and #closest_point_info here; callers that
  # already hold a Route instance should continue to use those delegating methods
  # rather than instantiating this service directly.
  #
  # == Methods
  #
  # closest_point_info(lat, lon)
  #   Returns the distance (metres) and fractional position (0.0–1.0) of the
  #   closest point on the route to the given coordinate. Used by
  #   Waypoint.calculate_sequence_for_position to place new waypoints correctly.
  #
  # points
  #   Returns an ActiveRecord relation of every vertex on the route with its
  #   cumulative distance from the start, using ST_DumpPoints. Useful for
  #   elevation charts and per-point analysis.
  #
  # boundaries
  #   Delegates straight to Boundary.intersecting_with_route — kept here so all
  #   spatial query concerns are co-located.
  #
  # @example
  #   service = Routes::GeometryService.new(route)
  #   service.closest_point_info(-23.5505, -46.6333)
  #   # => { distance: 142.3, fraction: 0.42 }
  #
  class GeometryService
    GEO_FACTORY = RGeo::Geographic.spherical_factory(srid: 4326)

    # @param route [Route]
    def initialize(route)
      @route = route
    end

    # Returns the distance and fractional position of the closest point on the
    # route to the given coordinate.
    #
    # Fraction is a value between 0.0 (route start) and 1.0 (route end),
    # suitable for comparing relative positions of points along the same route.
    #
    # @param lat [Float]
    # @param lon [Float]
    # @return [Hash] { distance: Float (metres), fraction: Float (0.0–1.0) }
    def closest_point_info(lat, lon)
      point = GEO_FACTORY.point(lon, lat)

      sql = <<~SQL
        SELECT
          ST_Distance(
            geom::geography,
            ST_GeomFromText('#{point.as_text}', 4326)::geography
          ) AS distance,
          ST_LineLocatePoint(
            geom::geometry,
            ST_ClosestPoint(
              geom::geometry,
              ST_GeomFromText('#{point.as_text}', 4326)::geometry
            )
          ) AS fraction
        FROM routes
        WHERE id = #{@route.id}
      SQL

      result = ActiveRecord::Base.connection.select_one(sql)

      {
        distance: result['distance'].to_f,
        fraction: result['fraction'].to_f
      }
    end

    # Returns an AR relation of every vertex in the route geometry, annotated
    # with the cumulative length of the line from the start to that point.
    #
    # Columns available on each result row:
    #   - id             [Integer]   route id
    #   - geom           [geometry]  the point geometry
    #   - segment_length [Float]     metres from route start to this point
    #
    # @return [ActiveRecord::Relation]
    def points
      joins_sql = <<~SQL
        JOIN (
          SELECT id AS route_id, ST_DumpPoints(geom::geometry) AS dp
          FROM routes
        ) AS dumped_points ON routes.id = dumped_points.route_id
      SQL

      select_sql = <<~SQL
        routes.id,
        (dp).geom,
        ST_Length(
          ST_GeometryN(ST_Split(routes.geom::geometry, (dp).geom), 1)::geography
        ) AS segment_length
      SQL

      Route.joins(joins_sql).where(id: @route.id).select(Arel.sql(select_sql))
    end

    # Returns the administrative and geographic boundaries that intersect
    # this route, ordered by their position along the line.
    #
    # @return [ActiveRecord::Relation<Boundary>]
    def boundaries
      Boundary.intersecting_with_route(@route.id)
    end
  end
end
