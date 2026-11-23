# frozen_string_literal: true

require 'test_helper'

module Landing
  class TripDistancesTest < ActiveSupport::TestCase
    include LandingTripHelpers

    setup do
      @trip = Trip.create!(name: 'Landing distances', start_on: Date.new(2027, 1, 30))
    end

    def route(**) = add_route(@trip, **)

    # PostGIS measures on the spheroid: a degree of latitude is about 110.7 km at
    # these latitudes, so km figures are compared within a small tolerance.
    def log(start_time, degrees)
      add_log(start_time, lat_from: -23.0, lat_to: -23.0 - degrees)
    end

    test 'planned km is the sum of the legs rounded to 100, falling back before any route exists' do
      assert_equal TripDistances::DEFAULT_PLANNED_KM, TripDistances.new(@trip).planned_km

      route(from_seq: 1, to_seq: 2, lat_from: -10, lat_to: -15) # about 553 km
      route(from_seq: 2, to_seq: 3, lat_from: -15, lat_to: -20) # about 553 km

      assert_equal 1100, TripDistances.new(@trip).planned_km
    end

    test 'driven km sums the logs since the start date and ignores earlier ones' do
      log(Time.utc(2027, 1, 20, 12), 3) # before the trip: a test drive
      log(Time.utc(2027, 2, 2, 12), 1)
      log(Time.utc(2027, 2, 3, 12), 2)

      assert_in_delta 332, TripDistances.new(@trip).driven_km, 2 # 3 degrees
    end

    test 'a drive starting just after midnight in Pesqueira on the start day counts' do
      # 02:00 UTC on 30 Jan is 23:00 on 29 Jan in Recife, so it is before the trip;
      # 04:00 UTC is 01:00 on 30 Jan in Recife, so it is on the first day.
      log(Time.utc(2027, 1, 30, 2), 1)
      log(Time.utc(2027, 1, 30, 4), 1)

      assert_in_delta 111, TripDistances.new(@trip).driven_km, 2 # only the second drive
    end

    test 'left km is rounded to 100 and never negative; percent is clamped' do
      route(from_seq: 1, to_seq: 2, lat_from: -10, lat_to: -15) # about 553 km, planned 600
      log(Time.utc(2027, 2, 2, 12), 2) # about 222 km

      d = TripDistances.new(@trip)
      assert_equal 600, d.planned_km
      assert_in_delta 222, d.driven_km, 2
      assert_equal 400, d.left_km
      assert_equal 37, d.percent

      log(Time.utc(2027, 2, 5, 12), 5) # now well past the plan
      over = TripDistances.new(@trip)
      assert_equal 0, over.left_km
      assert_equal 100, over.percent
    end
  end
end
