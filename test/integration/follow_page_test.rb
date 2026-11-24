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

  test 'a long trip shows 11 days around today, with arrows to the earlier and later days' do
    # 20 more days after the two from setup (all plain driving days, one route each).
    (3..22).each do |n|
      add_route(@trip, from_seq: n * 100, to_seq: (n + 1) * 100, lat_from: -23.0, lat_to: -24.0)
      route = @trip.routes.joins(:waypoint_start).find_by(waypoints: { sequence: n * 100 })
      route.update_columns(start_time: '1 day 8 hours')
    end
    # Day 16; the setup leaves day 2 as a rest day.
    travel_to(Time.find_zone!('America/Recife').local(2027, 2, 14, 12)) { get follow_path }

    assert_select 'a.day, .day', 11
    assert_select '.day.is-today .day-n', /16/
    assert_select 'a.pager-up[href=?]', follow_path(day: 5)
    assert_select 'a.pager-down[href=?]', follow_path(day: 23)

    get follow_path(day: 3)
    assert_select '.day', 11
    assert_select 'a.pager-up', 0 # already at the start
    assert_select 'a.pager-down[href=?]', follow_path(day: 17)
  end

  test 'the temperature curve shades the usual range when the estimate has deviations' do
    route = @trip.routes.joins(:waypoint_start).order('waypoints.sequence').first
    route.update_columns(segments: [{ 'distance' => 111_000, 'duration' => 5400 }])
    estimate = { lat: -22.0, lon: -46.6, planned_date: Date.new(2027, 1, 30),
                 temp_mean_c: 20, temp_min_c: 14, temp_max_c: 26,
                 source: 'climate_normal' }
    WeatherEstimate.create!(estimate.merge(temp_min_std: 2, temp_max_std: 3))
    get follow_route_path(route)

    assert_response :success
    assert_select 'svg.tcurve polygon', 1

    WeatherEstimate.delete_all
    WeatherEstimate.create!(estimate.merge(source: 'forecast'))
    get follow_route_path(route)

    assert_response :success
    assert_select 'svg.tcurve polyline', 1
    assert_select 'svg.tcurve polygon', 0 # a forecast has no deviation to show
  end

  test 'the temperature curve follows the car from the first waypoint\'s weather to the last\'s' do
    route = @trip.routes.joins(:waypoint_start).order('waypoints.sequence').first
    route.update_columns(segments: [{ 'distance' => 111_000, 'duration' => 5400 }]) # leaves 08:00, arrives 09:30
    date = Date.new(2027, 1, 30)
    cold = { lat: -21.0, lon: -46.6, planned_date: date, temp_mean_c: 5, temp_min_c: 0, temp_max_c: 10,
             source: 'forecast' }
    warm = { lat: -22.0, lon: -46.6, planned_date: date, temp_mean_c: 25, temp_min_c: 20, temp_max_c: 30,
             source: 'forecast' }
    [cold, warm].each { |attrs| WeatherEstimate.create!(attrs) }

    hourly = Follow::PlannedDay.new(route.reload).weather.hourly

    cold_only = Weather::HourlyTemperature.new(WeatherEstimate.find_by(lat: -21).to_weather_result,
                                               SolarPosition.new(date, route.waypoint_start.lonlat, SolarPosition::DEFAULT_TIMEZONE))
    assert_in_delta cold_only.at(2), hourly[2], 0.01 # before leaving: the first waypoint's weather
    assert_operator hourly[22], :>, 15 # after arriving: the last waypoint's

    # 09:00 is two thirds of the way from the first waypoint to the second, so it is
    # that share of the way between the two places' own 09:00 temperatures.
    solar = ->(wp) { SolarPosition.new(date, wp.lonlat, SolarPosition::DEFAULT_TIMEZONE) }
    at_nine = lambda do |attrs, wp|
      Weather::HourlyTemperature.new(WeatherEstimate.find_by(lat: attrs[:lat]).to_weather_result, solar.call(wp)).at(9)
    end
    from = at_nine.call(cold, route.waypoint_start)
    to = at_nine.call(warm, route.waypoint_end)
    assert_in_delta from + ((to - from) * (3600.0 / 5400)), hourly[9], 0.01
  end

  test 'a day opens its planned-day page for a viewer' do
    route = @trip.routes.joins(:waypoint_start).order('waypoints.sequence').first
    route.update_columns(segments: [{ 'distance' => 111_000, 'duration' => 5400 }])
    get follow_route_path(route)

    assert_response :success
    assert_select 'h1', 'Day 1 · wp100 → wp200'
    assert_select '[data-controller="follow-map"]'
    assert_select '.tl', 2
    assert_select 'svg.elev circle', 2 # the same two stops, numbered on the altitude profile
    assert_select '.stat-box .stat-num', '69 mi' # English shows miles, like the rest of the app
    last = @trip.routes.joins(:waypoint_start).order('waypoints.sequence').last
    assert_select 'a.btn-ghost[href=?]', follow_route_path(last), 'Day 3' # day 2 is a rest day in between
  end

  test 'distances, heights and temperatures follow the locale' do
    cookies[:locale] = 'pt'
    route = @trip.routes.joins(:waypoint_start).order('waypoints.sequence').first
    route.update_columns(segments: [{ 'distance' => 111_000, 'duration' => 5400 }])
    get follow_route_path(route)

    assert_select '.stat-box .stat-num', '111 km'
  end

  test 'the highest point says how far from the start it is' do
    cookies[:locale] = 'pt'
    route = @trip.routes.joins(:waypoint_start).order('waypoints.sequence').first
    route.update_columns(segments: [{ 'distance' => 111_000, 'duration' => 5400 }])
    Route.where(id: route.id).update_all(
      "geom = ST_GeogFromText('SRID=4326;LINESTRING ZM(-46.6 -23 0 0, -46.6 -24 3000 1)')"
    )
    get follow_route_path(route)

    # The line climbs to 3000 m at its far end, so the top is the whole day away.
    assert_select '.stat-box .stat-num', '3.000 m'
    assert_select '.stat-box .stat-sub', /a 111 km da saída/
  end

  test 'the day plan is the waypoint notes, in the visitor\'s language or the default' do
    route = @trip.routes.joins(:waypoint_start).order('waypoints.sequence').first
    route.update_columns(segments: [{ 'distance' => 111_000, 'duration' => 5400 }])
    Waypoint.where(trip: @trip, sequence: 200).update_all(notes: { 'en' => 'Lunch **early**.' })
    cookies[:locale] = 'pt' # no Portuguese note: falls back to English
    get follow_route_path(route)

    assert_select '.plan-text strong', 'early'
  end

  test 'a route that has not been calculated fails loudly' do
    route = @trip.routes.first
    get follow_route_path(route)

    assert_response :internal_server_error
  end
end
