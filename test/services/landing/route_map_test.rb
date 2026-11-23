# frozen_string_literal: true

require 'test_helper'

module Landing
  class RouteMapTest < ActiveSupport::TestCase
    include LandingTripHelpers

    HOME = MapProjection.project(RouteMap::HOME[:lon], RouteMap::HOME[:lat])

    setup do
      @trip = Trip.create!(name: 'Landing map', start_on: Date.new(2027, 1, 30))
      add_route(@trip, from_seq: 1, to_seq: 2, lat_from: -10, lat_to: -15)
      add_route(@trip, from_seq: 2, to_seq: 3, lat_from: -15, lat_to: -20)
    end

    def build(phase, fraction: 0.0)
      RouteMap.new(@trip, phase: phase, driven_fraction: fraction).build
    end

    def point(lat) = MapProjection.project(-46.6, lat)

    def path_start(lat) = "M#{point(lat).join(' ')}"

    test 'before the start the whole plan is still to go and the car sits at home' do
      map = build(:before)

      assert_equal '', map[:done_d]
      assert map[:todo_d].start_with?(path_start(-10)), map[:todo_d]
      assert_equal HOME, map[:position]
      assert_equal HOME, map[:home]
      assert_nil map[:place]
    end

    test 'during the trip: driven track in done, plan from the car onward in todo' do
      add_log(Time.utc(2027, 2, 1, 12), lat_from: -10.0, lat_to: -13.0)

      map = build(:during, fraction: 0.3)

      assert map[:done_d].start_with?(path_start(-10)), map[:done_d]
      assert_equal point(-13.0), map[:position]
      # The plan resumes at the vertex nearest the car (-15), so the first leg
      # (-10 to -15) is not drawn again as "to go".
      assert map[:todo_d].start_with?(path_start(-15)), map[:todo_d]
      assert_not_includes map[:todo_d], path_start(-10)
    end

    test 'driven segments are drawn in the order they were driven, not the order they arrived' do
      add_log(Time.utc(2027, 2, 3, 12), lat_from: -12.0, lat_to: -14.0) # arrives first, driven second
      add_log(Time.utc(2027, 2, 1, 12), lat_from: -10.0, lat_to: -12.0)

      map = build(:during, fraction: 0.3)

      assert map[:done_d].start_with?(path_start(-10)), map[:done_d]
      assert_equal point(-14.0), map[:position]
    end

    test 'the caption place is the nearest overnight stop to the car' do
      insert_waypoint(@trip, 10, name: 'Near', at: [-46.6, -13.2], type: 1)
      insert_waypoint(@trip, 11, name: 'Far', at: [-46.6, -19.0], type: 1)
      insert_waypoint(@trip, 12, name: 'Closer but a gas stop', at: [-46.6, -13.0], type: 7)
      add_log(Time.utc(2027, 2, 1, 12), lat_from: -10.0, lat_to: -13.0)

      assert_equal 'Near', build(:during, fraction: 0.3)[:place]
    end

    test 'back home: the whole drive is done, nothing is left to go' do
      add_log(Time.utc(2027, 2, 1, 12), lat_from: -10.0, lat_to: -20.0)

      map = build(:home, fraction: 1.0)

      assert_not_empty map[:done_d]
      assert_equal '', map[:todo_d]
    end

    test 'underway but no telemetry yet: car at home, plan intact' do
      map = build(:during)

      assert_equal '', map[:done_d]
      assert_equal HOME, map[:position]
      assert map[:todo_d].start_with?(path_start(-10)), map[:todo_d]
    end
  end
end
