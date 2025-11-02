# frozen_string_literal: true

class DashboardController < ApplicationController
  include DashboardDataBuilder

  layout 'welcome'

  def index
    @latest_log = TelemetryLog.order(timestamp: :desc).first
    @trip_detector = TripDetector.new
    @trip_detector.todays_trips(use_cache: false)

    # Get today's trips
    @todays_trips = TripLog.today.recent

    # Get today's distance from trip logs
    @today_distance_meters = TripLog.today.sum(&:distance)

    # Build initial dashboard data packet
    return unless @latest_log

    @initial_dashboard_data = build_dashboard_data(
      @latest_log,
      trip_detector: @trip_detector,
      today_distance_meters: @today_distance_meters
    )
  end
end
