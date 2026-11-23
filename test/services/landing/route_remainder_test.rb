# frozen_string_literal: true

require 'test_helper'

module Landing
  class RouteRemainderTest < ActiveSupport::TestCase
    OUT_AND_BACK = [
      [[0.0, 0.0], [10.0, 0.0], [20.0, 0.0]],
      [[20.0, 0.0], [10.0, 0.0], [0.0, 0.0]]
    ].freeze

    test 'returns the route from the car onward, the later legs untouched' do
      legs = [[[0.0, 0.0], [10.0, 0.0], [20.0, 0.0]], [[20.0, 0.0], [20.0, 10.0], [20.0, 20.0]]]

      remaining = RouteRemainder.after(legs, position: [10.0, 0.0], fraction: 0.25)

      assert_equal [[[10.0, 0.0], [20.0, 0.0]], legs[1]], remaining
    end

    test 'on a loop, the share already driven picks which pass the car is on' do
      outbound = RouteRemainder.after(OUT_AND_BACK, position: [10.0, 0.0], fraction: 0.25)
      returning = RouteRemainder.after(OUT_AND_BACK, position: [10.0, 0.0], fraction: 0.75)

      assert_equal [[10.0, 0.0], [20.0, 0.0]], outbound.first
      assert_equal [[[10.0, 0.0], [0.0, 0.0]]], returning
    end

    test 'position wins over the share driven when they disagree' do
      legs = [[[0.0, 0.0], [10.0, 0.0], [20.0, 0.0]]]

      # The share says "almost home" (detours made the odometer run ahead of the
      # plan) but the car is by the start: trust the position.
      remaining = RouteRemainder.after(legs, position: [1.0, 0.0], fraction: 1.0)

      assert_equal [[[0.0, 0.0], [10.0, 0.0], [20.0, 0.0]]], remaining
    end

    test 'no legs, nothing remaining' do
      assert_equal [], RouteRemainder.after([], position: [0.0, 0.0], fraction: 0.5)
    end
  end
end
