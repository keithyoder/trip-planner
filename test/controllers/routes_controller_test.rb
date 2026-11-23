# frozen_string_literal: true

require 'test_helper'

class RoutesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:keith)
    @trip = trips(:one)
  end

  test 'should get new' do
    get new_trip_route_url(@trip)
    assert_response :success
  end
end
