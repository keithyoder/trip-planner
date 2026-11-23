# frozen_string_literal: true

require 'test_helper'

# Waypoints are always nested under a trip (see config/routes.rb).
class WaypointsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:keith)
    @trip = trips(:one)
    @waypoint = waypoints(:one)
  end

  test 'should get index' do
    get trip_waypoints_url(@trip)
    assert_response :success
  end

  test 'should get new' do
    get new_trip_waypoint_url(@trip)
    assert_response :success
  end

  test 'should create waypoint' do
    assert_difference('Waypoint.count') do
      # latlon is always sent by the form; a waypoint without a location
      # makes the boundary assignment callback run SQL on an empty geometry.
      post trip_waypoints_url(@trip),
           params: { waypoint: { name: 'Created', sequence: 3, latlon: '-25.4284, -49.2733' } }
    end

    assert_redirected_to trip_waypoint_url(@trip, Waypoint.find_by!(name: 'Created'))
  end

  test 'should show waypoint' do
    get trip_waypoint_url(@trip, @waypoint)
    assert_response :success
  end

  test 'should get edit' do
    get edit_trip_waypoint_url(@trip, @waypoint)
    assert_response :success
  end

  test 'should update waypoint' do
    patch trip_waypoint_url(@trip, @waypoint), params: { waypoint: { name: 'Renamed' } }
    assert_redirected_to trip_waypoint_url(@trip, @waypoint)
    assert_equal 'Renamed', @waypoint.reload.name
  end

  test 'should destroy waypoint' do
    assert_difference('Waypoint.count', -1) do
      delete trip_waypoint_url(@trip, @waypoint)
    end

    assert_redirected_to trip_waypoints_url(@trip)
  end
end
