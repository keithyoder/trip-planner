class DashboardController < ApplicationController
  def index
    @latest_log = TelemetryLog.order(timestamp: :desc).first
    @is_travelling = check_if_travelling
  end

  private

  def check_if_travelling
    return false unless @latest_log

    # Check if there's been movement in the last 5 minutes
    recent_logs = TelemetryLog.where('timestamp >= ?', 5.minutes.ago).order(:timestamp)
    return false if recent_logs.count < 2

    # Check if speed is above threshold or if location has changed significantly
    speed = @latest_log.data['gps_speed']&.to_f || 0
    speed > 1.0 # Moving if speed > 1 m/s
  end
end
