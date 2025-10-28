# frozen_string_literal: true

class DashboardController < ApplicationController
  def index
    @latest_log = TelemetryLog.order(timestamp: :desc).first
    @trip_detector = TripDetector.instance
    @trip_detector.todays_trips
  end
end
