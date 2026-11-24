# frozen_string_literal: true

require 'test_helper'

class SolarPositionTest < ActiveSupport::TestCase
  Point = Struct.new(:latitude, :longitude)
  SANTIAGO = Point.new(-33.45, -70.67)

  def sunrise(date)
    SolarPosition.new(date, SANTIAGO, 'America/Santiago').sunrise.strftime('%H:%M')
  end

  test 'the day clocks change uses the new offset, not the one from the night before' do
    # Chile's clocks went back an hour at the end of Saturday 3 April 2027.
    assert_equal '07:55', sunrise(Date.new(2027, 4, 3))
    assert_equal '06:56', sunrise(Date.new(2027, 4, 4)) # was 07:56: an hour late
    assert_equal '06:56', sunrise(Date.new(2027, 4, 5))
  end
end
