# frozen_string_literal: true

require 'test_helper'

module Landing
  class OverviewTest < ActiveSupport::TestCase
    include LandingTripHelpers

    TODAY = Date.new(2027, 2, 10)

    setup do
      Trip.destroy_all
      @trip = Trip.create!(name: 'Overview trip', start_on: Date.new(2027, 1, 30), status: :in_progress)
      add_route(@trip, from_seq: 1, to_seq: 2, lat_from: -10, lat_to: -20)
      @original_cache = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
    end

    teardown { Rails.cache = @original_cache }

    def position(overview) = overview.map[:position]

    test 'builds from the current trip and exposes the counter and km' do
      overview = Overview.build(today: TODAY)

      assert_equal @trip, overview.trip
      assert_equal :during, overview.phase
      assert_equal 12, overview.days
      assert_equal 1100, overview.planned_km
      assert_equal 0, overview.driven_km
    end

    test 'fails loudly when there is no trip to talk about' do
      Trip.destroy_all

      error = assert_raises(Overview::NoTripError) { Overview.build(today: TODAY) }
      assert_match(/create a trip/, error.message)
    end

    test 'the map is cached for the day, so new telemetry does not rebuild it per request' do
      first = position(Overview.new(@trip, today: TODAY))
      add_log(Time.find_zone!('America/Recife').local(2027, 2, 5, 9), lat_from: -10.0, lat_to: -14.0)

      assert_equal first, position(Overview.new(@trip, today: TODAY))
    end

    test 'refresh_map! rebuilds it on demand' do
      overview = Overview.new(@trip, today: TODAY)
      before = position(overview)
      add_log(Time.find_zone!('America/Recife').local(2027, 2, 5, 9), lat_from: -10.0, lat_to: -14.0)

      overview.refresh_map!

      assert_not_equal before, position(Overview.new(@trip, today: TODAY))
    end

    test 'the next day starts a fresh map by itself' do
      before = position(Overview.new(@trip, today: TODAY))
      add_log(Time.find_zone!('America/Recife').local(2027, 2, 5, 9), lat_from: -10.0, lat_to: -14.0)

      assert_not_equal before, position(Overview.new(@trip, today: TODAY + 1))
    end
  end
end
