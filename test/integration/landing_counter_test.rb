# frozen_string_literal: true

require 'test_helper'

# The green counter, the km stats, the progress bar and the map caption in each
# phase of the trip. Time is frozen in Pesqueira's zone, where days are counted.
class LandingCounterTest < ActionDispatch::IntegrationTest
  include LandingTripHelpers

  START = Date.new(2027, 1, 30)

  setup do
    Trip.destroy_all
    @trip = Trip.create!(name: 'Landing trip', start_on: START)
    cookies[:locale] = 'pt'
  end

  def recife(year, month, day)
    Time.find_zone!('America/Recife').local(year, month, day, 12)
  end

  def landing_on(time)
    travel_to(time) { get root_path }
    assert_response :success
  end

  test 'before the start: days to go and planned km, no progress bar' do
    landing_on recife(2027, 1, 20)

    assert_select '.stat-count .stat-num', '10'
    assert_select '.stat-count .stat-label', 'dias para a partida'
    assert_select '.stat .stat-label', 'km planejados'
    assert_select '.stat .stat-num', '30.000'
    assert_select '[role="progressbar"]', 0
    assert_select '.map-now', 'Partida: Pesqueira, PE'
  end

  test 'the day before is singular' do
    landing_on recife(2027, 1, 29)

    assert_select '.stat-count .stat-num', '1'
    assert_select '.stat-count .stat-label', 'dia para a partida'
  end

  test 'on the start day the counter says Today' do
    landing_on recife(2027, 1, 30)

    assert_select '.stat-count .stat-num', 'Hoje'
    assert_select '.stat-count .stat-label', 'partimos hoje'
  end

  test 'English counter formats numbers the English way' do
    cookies[:locale] = 'en'
    landing_on recife(2027, 1, 20)

    assert_select '.stat .stat-num', '30,000'
    assert_select '.stat-count .stat-label', 'days until we leave'
  end

  test 'during the trip: day number, km driven, km to go, progress bar and the nearest stop' do
    @trip.update!(status: :in_progress)
    add_route(@trip, from_seq: 1, to_seq: 2, lat_from: -10, lat_to: -20) # about 1,100 km
    insert_waypoint(@trip, 10, name: 'Paraty', at: [-46.6, -14.1], type: 1)
    add_log(Time.find_zone!('America/Recife').local(2027, 2, 1, 9), lat_from: -10.0, lat_to: -14.0)

    landing_on recife(2027, 2, 12)

    assert_select '.stat-count .stat-num', '14'
    assert_select '.stat-count .stat-label', 'dias de viagem'
    assert_select '.stat .stat-label', 'km rodados'
    assert_select '.stat .stat-label', 'km faltando'
    assert_select '.stat .stat-num', text: /\A≈ /
    assert_select '[role="progressbar"][aria-valuenow]'
    assert_select '.map-now', 'Hoje: perto de Paraty'
  end

  test 'back home: the total, no end date and no progress bar' do
    @trip.update!(status: :completed)
    add_log(Time.find_zone!('America/Recife').local(2027, 2, 1, 9), lat_from: -10.0, lat_to: -20.0)

    landing_on recife(2027, 5, 25)

    assert_select '.stat-count .stat-label', 'dias de viagem, já em casa'
    assert_select '.stat .stat-label', 'km rodados no total'
    assert_select '[role="progressbar"]', 0
    assert_select '.map-now', 'De volta a Pesqueira, PE'
  end
end
