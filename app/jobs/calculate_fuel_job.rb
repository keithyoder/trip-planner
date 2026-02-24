# frozen_string_literal: true

class CalculateFuelJob < ApplicationJob
  queue_as :default

  # @param trip_id [Integer]
  def perform(trip_id)
    trip = Trip.find(trip_id)
    Trips::FuelCalculator.new(trip).calculate
  end
end
