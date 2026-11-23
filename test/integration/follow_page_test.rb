# frozen_string_literal: true

require 'test_helper'

class FollowPageTest < ActionDispatch::IntegrationTest
  include LandingTripHelpers

  setup do
    Trip.destroy_all
    @trip = Trip.create!(name: 'Follow trip', start_on: Date.new(2027, 1, 30), status: :in_progress)
    add_route(@trip, from_seq: 100, to_seq: 200, lat_from: -23.0, lat_to: -24.0)
    add_route(@trip, from_seq: 200, to_seq: 300, lat_from: -24.0, lat_to: -25.0)
    @trip.routes.joins(:waypoint_start).order('waypoints.sequence').zip(['8 hours', '2 days 8 hours']) do |route, time|
      route.update_columns(start_time: time)
    end
    @trip.waypoints.find_each do |wp|
      lat = -20.0 - (wp.sequence / 100)
      Waypoint.where(id: wp.id).update_all("lonlat = ST_GeogFromText('SRID=4326;POINT(-46.6 #{lat})')")
    end
    cookies[:locale] = 'en'
    sign_in users(:watcher)
  end

  test 'lists the days, with rest days not linked, and the Live link' do
    travel_to(Time.find_zone!('America/Recife').local(2027, 2, 1, 12)) { get follow_path }

    assert_response :success
    assert_select 'a.day', 2
    assert_select '.day.is-rest .day-title', 'Rest day in wp200'
    assert_select '.day.is-rest a', 0
    assert_select 'a.nav-link[href=?]', dashboard_path
    assert_select 'button.logout', 'Log out'
  end

  test 'countries after the current one are summarised under Later' do
    # Country comes from the arrival waypoint's level-2 boundary: give the two days different ones.
    countries = [%w[Brasil 1], %w[Uruguay 2]]
    waypoints = @trip.waypoints.order(:sequence).to_a
    [waypoints[1], waypoints[2]].zip(countries).each do |wp, (name, osm)|
      boundary = Boundary.create!(name: name, level: 2, osm_id: osm.to_i + 9000)
      ActiveRecord::Base.connection.execute("INSERT INTO boundaries_waypoints (boundary_id, waypoint_id) VALUES (#{boundary.id}, #{wp.id})")
    end
    travel_to(Time.find_zone!('America/Recife').local(2027, 1, 30, 12)) { get follow_path }

    assert_response :success
    assert_select '.later li strong', 'Uruguay'
  end

  test 'a day opens its planned-day page for a viewer' do
    route = @trip.routes.joins(:waypoint_start).order('waypoints.sequence').first
    route.update_columns(segments: [{ 'distance' => 111_000, 'duration' => 5400 }])
    get follow_route_path(route)

    assert_response :success
    assert_select 'h1', 'Day 1 · wp100 → wp200'
    assert_select '[data-controller="follow-map"]'
    assert_select '.tl', 2
    assert_select '.stat-box .stat-num', '111'
    assert_select 'a.btn-ghost[href=?]', follow_route_path(@trip.routes.joins(:waypoint_start).order('waypoints.sequence').last)
  end

  test 'a route that has not been calculated fails loudly' do
    route = @trip.routes.first
    get follow_route_path(route)

    assert_response :internal_server_error
  end
end
