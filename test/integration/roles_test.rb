# frozen_string_literal: true

require 'test_helper'

# Admins edit; everyone else only sees /follow. Controllers are admin-only by
# default, so these pin the default and the two deliberate exceptions.
class RolesTest < ActionDispatch::IntegrationTest
  test 'new users are viewers' do
    assert_predicate User.create!(email: 'new@example.com'), :viewer?
  end

  test 'a viewer is sent to /follow from admin pages' do
    sign_in users(:watcher)
    [trips_path, new_trip_path].each do |path|
      get path
      assert_redirected_to follow_path, path
    end
  end

  test 'a viewer cannot change data' do
    sign_in users(:watcher)
    assert_no_difference 'Trip.count' do
      post trips_path, params: { trip: { name: 'x' } }
    end
    assert_redirected_to follow_path
  end

  test 'a viewer can open the live dashboard, which the Live link points to' do
    sign_in users(:watcher)
    get dashboard_path
    assert_response :success
  end

  test 'a viewer can open /follow' do
    sign_in users(:watcher)
    get follow_path
    assert_response :success
  end

  test 'an admin keeps the planner and can also open /follow' do
    sign_in users(:keith)
    get trips_path
    assert_response :success
    get follow_path
    assert_response :success
  end

  test 'an anonymous visitor is sent to the login' do
    get follow_path
    assert_redirected_to new_user_session_path
  end
end
