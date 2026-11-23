# frozen_string_literal: true

require 'test_helper'

module Landing
  class TripDistancesTest < ActiveSupport::TestCase
    FACTORY = RGeo::Geographic.spherical_factory(srid: 4326)

    setup do
      @trip = Trip.create!(name: 'Landing distances', start_on: Date.new(2027, 1, 30))
    end

    # Routes are inserted directly: Route's callbacks enqueue a call to the
    # routing API, which a unit test must never trigger.
    def add_route(from_seq:, to_seq:, lat_from:, lat_to:)
      ids = [from_seq, to_seq].map do |seq|
        Waypoint.find_by(trip: @trip, sequence: seq)&.id || insert_waypoint(seq)
      end
      ActiveRecord::Base.connection.execute(<<~SQL.squish)
        INSERT INTO routes (waypoint_start_id, waypoint_end_id, trip_id, geom, created_at, updated_at)
        VALUES (#{ids[0]}, #{ids[1]}, #{@trip.id},
          ST_GeogFromText('SRID=4326;LINESTRING ZM(-46.6 #{lat_from} 0 0, -46.6 #{lat_to} 0 1)'), now(), now())
      SQL
    end

    def insert_waypoint(sequence)
      Waypoint.insert_all([{ trip_id: @trip.id, name: "wp#{sequence}", sequence: sequence,
                             created_at: Time.current, updated_at: Time.current }]).first['id']
    end

    # One degree of latitude is about 110.7 km at these latitudes (PostGIS
    # measures on the spheroid), so the tests compare within a small tolerance.
    def add_log(start_time, degrees_of_latitude)
      line = FACTORY.line_string([FACTORY.point(-46.6, -23.0), FACTORY.point(-46.6, -23.0 - degrees_of_latitude)])
      TripLog.create!(start_time: start_time, end_time: start_time + 1.hour, geom: line, data: {})
    end

    test 'planned km is the sum of the legs rounded to 100, falling back before any route exists' do
      assert_equal TripDistances::DEFAULT_PLANNED_KM, TripDistances.new(@trip).planned_km

      add_route(from_seq: 1, to_seq: 2, lat_from: -10, lat_to: -15) # about 553 km
      add_route(from_seq: 2, to_seq: 3, lat_from: -15, lat_to: -20) # about 553 km

      assert_equal 1100, TripDistances.new(@trip).planned_km
    end

    test 'driven km sums the logs since the start date and ignores earlier ones' do
      add_log(Time.utc(2027, 1, 20, 12), 3) # before the trip: a test drive
      add_log(Time.utc(2027, 2, 2, 12), 1)
      add_log(Time.utc(2027, 2, 3, 12), 2)

      assert_in_delta 332, TripDistances.new(@trip).driven_km, 2 # 3 degrees
    end

    test 'a drive starting just after midnight in Pesqueira on the start day counts' do
      # 02:00 UTC on 30 Jan is 23:00 on 29 Jan in Recife, so it is before the trip;
      # 04:00 UTC is 01:00 on 30 Jan in Recife, so it is on the first day.
      add_log(Time.utc(2027, 1, 30, 2), 1)
      add_log(Time.utc(2027, 1, 30, 4), 1)

      assert_in_delta 111, TripDistances.new(@trip).driven_km, 2 # only the second drive
    end

    test 'left km is rounded to 100 and never negative; percent is clamped' do
      add_route(from_seq: 1, to_seq: 2, lat_from: -10, lat_to: -15) # about 553 km, planned 600
      add_log(Time.utc(2027, 2, 2, 12), 2) # about 222 km

      d = TripDistances.new(@trip)
      assert_equal 600, d.planned_km
      assert_in_delta 222, d.driven_km, 2
      assert_equal 400, d.left_km
      assert_equal 37, d.percent

      add_log(Time.utc(2027, 2, 5, 12), 5) # now well past the plan
      over = TripDistances.new(@trip)
      assert_equal 0, over.left_km
      assert_equal 100, over.percent
    end
  end
end
