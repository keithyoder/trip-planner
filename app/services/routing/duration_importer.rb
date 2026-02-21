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
  # there is no preceding point to measure distance from.
  #
  # == Usage
  #
  #   Routes::DurationImporter.new(route).import
  #
  # The route must have:
  #   - +geom+     a 3D LineString (populated by OrsService#calculate)
  #   - +segments+ the ORS segments JSON (populated by OrsService#calculate)
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
    # @return [Array<Array<Numeric>>] coordinate tuples [x, y, z, m]
    def stamp_coordinates
      line = RGeo::GeoJSON.encode(@route.geom)
      coords = line['coordinates']
      waypoints = @route.waypoints.to_a
      elapsed = 0.0

      @route.segments.each do |segment|
        # Each segment starts at a waypoint; accumulate any stop delay there.
        waypoint = waypoints.shift
        elapsed += waypoint.delay.to_f if waypoint

        segment['steps'].each do |step|
          first_idx = step['way_points'].first
          last_idx  = step['way_points'].last

          # A step covering only one point has no distance to calculate from.
          next if first_idx >= last_idx

          velocity = step_velocity(step)

          (first_idx + 1..last_idx).each do |idx|
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
    # We write raw SQL rather than assigning to geom so that PostGIS handles
    # the geometry parsing — RGeo does not support 4D geometries natively.
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

    # @param coordinates [Array<Array<Numeric>>]
    # @return [String] WKT LINESTRING ZM (...)
    def build_linestring_zm(coordinates)
      points = coordinates.map { |c| c.join(' ') }.join(', ')
      "LINESTRING ZM (#{points})"
    end
  end
end
