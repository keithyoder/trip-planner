# frozen_string_literal: true

# Builds the rows the landing-page services read (routes, waypoints, telemetry
# logs) without Route/Waypoint callbacks: those enqueue calls to the routing and
# boundary services, which a test must never trigger.
module LandingTripHelpers
  FACTORY = RGeo::Geographic.spherical_factory(srid: 4326)

  # `at` is [lon, lat].
  def insert_waypoint(trip, sequence, name: "wp#{sequence}", at: nil, type: nil)
    row = { trip_id: trip.id, name: name, sequence: sequence, waypoint_type: type,
            created_at: Time.current, updated_at: Time.current }
    row[:lonlat] = "POINT(#{at[0]} #{at[1]})" if at
    Waypoint.insert_all([row]).first['id']
  end

  # A straight north-south route between two latitudes along lon -46.6, linking
  # waypoints with the given sequence numbers (created if missing).
  def add_route(trip, from_seq:, to_seq:, lat_from:, lat_to:)
    ids = [from_seq, to_seq].map { |seq| Waypoint.find_by(trip: trip, sequence: seq)&.id || insert_waypoint(trip, seq) }
    ActiveRecord::Base.connection.execute(<<~SQL.squish)
      INSERT INTO routes (waypoint_start_id, waypoint_end_id, trip_id, geom, created_at, updated_at)
      VALUES (#{ids[0]}, #{ids[1]}, #{trip.id},
        ST_GeogFromText('SRID=4326;LINESTRING ZM(-46.6 #{lat_from} 0 0, -46.6 #{lat_to} 0 1)'), now(), now())
    SQL
  end

  # A telemetry segment along lon -46.6 between two latitudes.
  def add_log(start_time, lat_from: -23.0, lat_to: -24.0)
    line = FACTORY.line_string([FACTORY.point(-46.6, lat_from), FACTORY.point(-46.6, lat_to)])
    TripLog.create!(start_time: start_time, end_time: start_time + 1.hour, geom: line, data: {})
  end
end
