# frozen_string_literal: true

class DashboardController < ApplicationController
  layout 'welcome'

  def index
    @latest_log = TelemetryLog.order(timestamp: :desc).first
    @trip_detector = TripDetector.new
    @trip_detector.todays_trips(use_cache: true)

    # Get today's trips
    @todays_trips = TripLog.today.recent

    # Get today's distance from trip logs
    @today_distance_meters = TripLog.today.sum(&:distance)
  end
end
