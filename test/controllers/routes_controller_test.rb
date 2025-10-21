# frozen_string_literal: true

require 'test_helper'

class RoutesControllerTest < ActionDispatch::IntegrationTest
  test 'should get new' do
    get routes_new_url
    assert_response :success
  end
end
