# frozen_string_literal: true

module Routing
  # Stamps cumulative travel time (in seconds) into the M dimension of each
  # coordinate in a route's LineString geometry.
  #
  # == Background
  #
  # ORS returns a 3D geometry (XYZ = lon/lat/elevation). This service adds a
  # fourth dimension (M) representing elapsed time from the trip start, turning
  # the geometry into a 4D XYZM LineString. This allows later spatial queries
  # to answer "where was the vehicle at time T?" by interpolating along the line.
  #
  # == Algorithm
  #
  # ORS segments map 1:1 with the gaps between waypoints. For each segment:
  #   1. Add the waypoint's stop delay (e.g. 15 min fuel stop) to the running total.
  #   2. Walk each step within the segment, computing elapsed time from
  #      distance / velocity and accumulating it into the M value of each point.
  #
  # Single-point steps (way_points.first == way_points.last) are skipped because
  # there is no preceding point to measure distance from — except for the final
  # arrival step, which is stamped with the current elapsed time so that
  # build_arrival_time can read the M value of the last coordinate.
  #
  # == Usage
  #
  #   Routing::DurationImporter.new(route).import
  #
  # The route must have:
  #   - +geom+     a 3D LineString (populated by MergeService)
  #   - +segments+ the ORS segments JSON (populated by MergeService)
  #   - +waypoints+ ordered waypoints with optional +delay+ values (seconds)
  #
  class DurationImporter
    GEO_FACTORY = RGeo::Geographic.spherical_factory(srid: 4326)

    # @param route [Route]
    def initialize(route)
      @route = route
    end

    # Runs the import and persists the stamped geometry.
    #
    # @return [void]
    def import
      coordinates = stamp_coordinates
      persist(coordinates)
    end

    private

    # Walks segments and steps, returning the full coordinate array with M values
    # set to cumulative elapsed seconds.
    #
    # Coordinates are read directly from PostGIS via ST_AsGeoJSON rather than
    # through RGeo, which drops points on 4D geometries.
    #
    # @return [Array<Array<Numeric>>] coordinate tuples [x, y, z, m]
    def stamp_coordinates
      result = Route.connection.exec_query(
        Route.sanitize_sql(
          ['SELECT ST_AsGeoJSON(geom) AS geojson FROM routes WHERE id = :id', { id: @route.id }]
        )
      ).first
      coords    = JSON.parse(result['geojson'])['coordinates']
      waypoints = @route.waypoints.reject(&:routing?).to_a
      elapsed   = 0.0

      @route.segments.each_with_index do |segment, i|
        # Apply the departing waypoint's stop delay before walking this segment.
        waypoint = waypoints[i]
        elapsed += waypoint.delay.to_f if waypoint

        segment['steps'].each do |step|
          first_idx = step['way_points'].first
          last_idx  = step['way_points'].last

          # Stamp the arrival step's coordinate with current elapsed time even
          # though it covers no distance — this is what build_arrival_time reads.
          if first_idx >= last_idx
            coords[first_idx][3] = elapsed if first_idx < coords.size
            next
          end

          velocity = step_velocity(step)

          (first_idx + 1..last_idx).each do |idx|
            next if idx >= coords.size

            dist = distance_between(coords[idx], coords[idx - 1])
            elapsed += dist / velocity unless velocity.nan? || velocity.zero?
            coords[idx][3] = elapsed
          end
        end
      end

      coords
    end

    # Persists the stamped coordinates as a LINESTRING ZM geography.
    #
    # Written as raw SQL because RGeo does not support 4D geometries natively.
    #
    # @param coordinates [Array<Array<Numeric>>]
    # @return [void]
    def persist(coordinates)
      wkt = build_linestring_zm(coordinates)

      Route.connection.exec_update(
        Route.sanitize_sql(
          [
            'UPDATE routes SET geom = ST_GeomFromText(:geom)::geography WHERE id = :id',
            { id: @route.id, geom: wkt }
          ]
        )
      )
    end

    # @param step [Hash] an ORS step with 'distance' and 'duration' keys
    # @return [Float] metres per second
    def step_velocity(step)
      duration = step['duration'].to_f
      return Float::NAN if duration.zero?

      step['distance'].to_f / duration
    end

    # Calculates the spherical distance in metres between two coordinate tuples.
    #
    # @param pt1 [Array] [x, y, ...]
    # @param pt2 [Array] [x, y, ...]
    # @return [Float] distance in metres
    def distance_between(pt1, pt2)
      GEO_FACTORY.point(pt1[0], pt1[1])
                 .distance(GEO_FACTORY.point(pt2[0], pt2[1]))
    end

    # Builds a LINESTRING ZM WKT string from a coordinate array.
    # Ensures every point has X, Y, Z, M — defaulting Z and M to 0 if missing.
    #
    # @param coordinates [Array<Array<Numeric>>]
    # @return [String] WKT LINESTRING ZM (...)
    def build_linestring_zm(coordinates)
      points = coordinates.map do |c|
        x, y, z, m = c
        "#{x} #{y} #{z || 0} #{m || 0}"
      end.join(', ')
      "LINESTRING ZM (#{points})"
    end
  end
end
