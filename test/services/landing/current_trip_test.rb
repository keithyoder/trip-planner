# frozen_string_literal: true

require 'test_helper'

module Landing
  class CurrentTripTest < ActiveSupport::TestCase
    TODAY = Date.new(2027, 1, 1)

    setup do
      # Start from a clean slate: the shared fixtures also contain trips.
      Trip.destroy_all
    end

    test 'nil when there are no trips' do
      assert_nil CurrentTrip.find(today: TODAY)
    end

    test 'the trip underway wins over everything' do
      Trip.create!(name: 'next', start_on: TODAY + 10)
      underway = Trip.create!(name: 'underway', start_on: TODAY - 5, status: :in_progress)

      assert_equal underway, CurrentTrip.find(today: TODAY)
    end

    test 'otherwise the soonest planned trip that has not started, ignoring ones already past' do
      Trip.create!(name: 'stale plan', start_on: TODAY - 400)
      Trip.create!(name: 'later', start_on: TODAY + 90)
      soonest = Trip.create!(name: 'soonest', start_on: TODAY + 30)

      assert_equal soonest, CurrentTrip.find(today: TODAY)
    end

    test 'a planned trip starting today still counts as upcoming' do
      todays = Trip.create!(name: 'leaving today', start_on: TODAY)

      assert_equal todays, CurrentTrip.find(today: TODAY)
    end

    test 'otherwise the most recent trip that has started' do
      Trip.create!(name: 'old', start_on: TODAY - 800, status: :completed)
      recent = Trip.create!(name: 'recent', start_on: TODAY - 300, status: :completed)

      assert_equal recent, CurrentTrip.find(today: TODAY)
    end

    test 'a trip whose start date passed but was never marked in progress still counts' do
      Trip.create!(name: 'old', start_on: TODAY - 800, status: :completed)
      forgotten = Trip.create!(name: 'forgot to flip', start_on: TODAY - 3)

      assert_equal forgotten, CurrentTrip.find(today: TODAY)
    end

    test 'skipped trips are never chosen' do
      Trip.create!(name: 'skipped', start_on: TODAY - 3, status: :skipped)

      assert_nil CurrentTrip.find(today: TODAY)
    end
  end
end
