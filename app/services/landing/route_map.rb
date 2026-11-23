# frozen_string_literal: true

module Landing
  # The moving parts of the landing page's hero map, as SVG path data in the
  # map's own coordinates: the planned route still to go, the track already
  # driven, the car's position, and the nearest overnight stop for the caption.
  # The country outlines are static (see CountryOutlines).
  #
  # The caller caches the result; computing it queries PostGIS and is meant to
  # run about once a day, not on every page view.
  class RouteMap
    # Degrees. At the map's scale (about 0.18 degree per pixel) this is
    # imperceptible, and it keeps the SVG small.
    SIMPLIFY_TOLERANCE = 0.05

    # Pesqueira, PE: the start and, eventually, the finish.
    HOME = { lon: -36.6975, lat: -8.3593 }.freeze

    def initialize(trip, phase:, driven_fraction: 0.0)
      @trip = trip
      @phase = phase
      @driven_fraction = driven_fraction.clamp(0.0, 1.0)
    end

    # @return [Hash] done_d / todo_d are SVG path "d" strings (possibly empty),
    #   position and home are [x, y], place is a name or nil.
    def build
      home = project_point([HOME[:lon], HOME[:lat]])
      return result(home: home, position: home, todo: project(planned_lines)) unless underway?

      underway_result(home)
    end

    private

    def underway?
      %i[during home].include?(@phase)
    end

    def underway_result(home)
      driven = driven_lines
      here = driven.last&.last
      position = here ? project_point(here) : home
      result(home: home, position: position, done: project(driven), todo: todo_after(position), place: place_near(here))
    end

    def todo_after(position)
      return [] if @phase == :home

      RouteRemainder.after(project(planned_lines), position: position, fraction: @driven_fraction)
    end

    def result(home:, position:, done: [], todo: [], place: nil)
      { done_d: path_data(done), todo_d: path_data(todo), position: position, home: home, place: place }
    end

    def path_data(legs)
      legs.filter_map do |points|
        next if points.size < 2

        "M#{points.map { |x, y| "#{x} #{y}" }.join('L')}"
      end.join
    end

    def project(lines)
      lines.map { |line| line.map { |point| project_point(point) } }
    end

    def project_point(point)
      MapProjection.project(point[0], point[1])
    end

    # Planned legs in route order, each an array of [lon, lat].
    def planned_lines
      @planned_lines ||= geojson_lines(<<~SQL.squish)
        SELECT ST_AsGeoJSON(ST_Simplify(r.geom::geometry, #{SIMPLIFY_TOLERANCE}, true), 5)
        FROM routes r JOIN route_sequences rs ON rs.route_id = r.id
        WHERE r.trip_id = #{@trip.id.to_i} AND r.geom IS NOT NULL
        ORDER BY rs.sequence
      SQL
    end

    # Telemetry segments since the trip started, in the order they were driven
    # (by timestamp, never by id: messages can arrive hours late).
    def driven_lines
      from = Time.find_zone!(TripPhase::ZONE).local(@trip.start_on.year, @trip.start_on.month, @trip.start_on.day)
      geojson_lines(ActiveRecord::Base.sanitize_sql_array([<<~SQL.squish, from]))
        SELECT ST_AsGeoJSON(ST_Simplify(geom::geometry, #{SIMPLIFY_TOLERANCE}, true), 5)
        FROM trip_logs WHERE start_time >= ? AND geom IS NOT NULL
        ORDER BY start_time
      SQL
    end

    # Each result row is one GeoJSON line (or multi-line); points keep only
    # lon/lat (the routes also carry elevation and time as extra values).
    def geojson_lines(sql)
      ActiveRecord::Base.connection.select_values(sql).flat_map do |json|
        geometry = JSON.parse(json)
        lines = geometry['type'] == 'MultiLineString' ? geometry['coordinates'] : [geometry['coordinates']]
        lines.map { |line| line.map { |lon, lat| [lon, lat] } }
      end
    end

    # Nearest overnight stop to where the car is, for "Today: near ...".
    def place_near(lonlat)
      return nil unless lonlat

      order = ActiveRecord::Base.sanitize_sql_array(
        ['lonlat <-> ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography', lonlat[0], lonlat[1]]
      )
      Waypoint.overnight.where(trip_id: @trip.id).where.not(lonlat: nil).order(Arel.sql(order)).limit(1).pick(:name)
    end
  end
end
