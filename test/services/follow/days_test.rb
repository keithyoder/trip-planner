# frozen_string_literal: true

require 'test_helper'

module Follow
  class DaysTest < ActiveSupport::TestCase
    include LandingTripHelpers

    setup do
      Trip.destroy_all
      @trip = Trip.create!(name: 'Days trip', start_on: Date.new(2027, 1, 30))
      # Days 1, 2 and 4: nobody drives on day 3.
      add_route(@trip, from_seq: 100, to_seq: 200, lat_from: -23.0, lat_to: -24.0)
      add_route(@trip, from_seq: 200, to_seq: 300, lat_from: -24.0, lat_to: -25.0)
      add_route(@trip, from_seq: 300, to_seq: 400, lat_from: -25.0, lat_to: -26.0)
      set_start_times('8 hours', '1 day 8 hours', '2 days 8 hours')
    end

    def ordered_routes
      @trip.routes.joins(:waypoint_start).order('waypoints.sequence')
    end

    def set_start_times(*times)
      ordered_routes.zip(times) { |route, time| route.update_columns(start_time: time) }
    end

    def days(today:)
      Days.new(@trip, today: today).call.groups.flat_map(&:days)
    end

    test 'a route is a day, and the days nobody drives become rest days' do
      list = days(today: Date.new(2027, 1, 30))

      assert_equal [1, 2, 3, 4], list.map(&:number)
      assert_equal [false, false, true, false], list.map(&:rest?)
      assert_equal Date.new(2027, 2, 1), list[2].date
      assert_equal 'wp300', list[2].to # a rest day is spent where the previous day ended
    end

    test 'states follow the route status and today\'s date' do
      ordered_routes.first.update_columns(status: Route.statuses[:completed])
      list = days(today: Date.new(2027, 1, 31))

      assert_equal %i[done today planned planned], list.map(&:state)
    end

    test 'the current day is the one in progress, else the next planned one' do
      assert_equal 1, Days.new(@trip, today: Date.new(2027, 1, 1)).call.current.number
    end

    test 'skipped routes are left out' do
      ordered_routes.last.update_columns(status: Route.statuses[:skipped])

      assert_equal [1, 2], days(today: Date.new(2027, 1, 30)).map(&:number)
    end

    test 'a route without a computed date raises instead of vanishing from the list' do
      ordered_routes.first.update_columns(start_time: nil)

      assert_raises(Days::Undated) { Days.new(@trip).call }
    end
  end
end
