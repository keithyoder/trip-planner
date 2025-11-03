# frozen_string_literal: true

require 'dashboard_data_builder'

# DashboardController
#
# Handles dashboard display and provides JSON API for async data loading.
# The index action responds to both HTML and JSON formats.
#
class DashboardController < ApplicationController
  include DashboardDataBuilder
  layout 'welcome'

  # GET /dashboard
  # GET /dashboard.json
  #
  # HTML: Renders the dashboard view (data loaded via JavaScript)
  # JSON: Returns current dashboard state including GPS, trip status, and weather data
  def index
    respond_to do |format|
      format.html do
        # Just render the view - data will be loaded asynchronously via JavaScript
      end

      format.json do
        latest_log = TelemetryLog.with_gps.recent.first

        if latest_log.nil?
          render json: { error: 'No telemetry data available' }, status: :not_found
          return
        end

        trip_detector = TripDetector.instance
        trip_detector.todays_trips
        today_distance = calculate_today_distance_meters(trip_detector)

        data = build_dashboard_data(
          latest_log,
          trip_detector: trip_detector,
          today_distance_meters: today_distance
        )

        # Add trip polyline points if currently travelling
        data[:trip_points] = trip_detector.current_trip_points if trip_detector.currently_travelling?

        # Add today's trips from TripLog (saved trips with geom)
        todays_trip_logs = TripLog.today.recent.to_a
        data[:todays_trips] = {
          trips: todays_trip_logs.map { |trip_log| format_trip_log(trip_log) },
          summary: calculate_trips_summary(todays_trip_logs)
        }

        render json: data
      end
    end
  end

  # GET /dashboard/trips/today
  # Returns all trips detected for today
  def todays_trips
    trip_detector = TripDetector.instance
    trips = trip_detector.todays_trips

    render json: {
      trips: trips.map { |t| format_trip(t) },
      summary: trip_detector.trip_summary(trips)
    }
  end

  private

  def calculate_today_distance_meters(trip_detector)
    distance_meters = TripLog.today.to_a.sum(&:distance)
    distance_meters += trip_detector.current_trip[:total_distance] if trip_detector.current_trip
    distance_meters
  end

  def format_trip_log(trip_log) # rubocop:disable Metrics/AbcSize
    {
      id: trip_log.id,
      name: trip_log.name,
      start_time: trip_log.start_time.iso8601,
      end_time: trip_log.end_time.iso8601,
      duration_seconds: trip_log.duration,
      duration_minutes: trip_log.duration_minutes,
      distance_meters: trip_log.distance.round(2),
      distance_km: trip_log.distance_km,
      max_speed_ms: trip_log.max_speed,
      max_speed_kmh: trip_log.max_speed_kmh,
      avg_speed_ms: trip_log.avg_speed,
      avg_speed_kmh: trip_log.avg_speed_kmh,
      start_location: trip_log.start_location,
      end_location: trip_log.end_location,
      point_count: trip_log.point_count,
      coordinates: trip_log.coordinates # Extracted from geom
    }
  end

  def calculate_trips_summary(trip_logs) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
    return default_summary if trip_logs.empty?

    total_distance = trip_logs.sum(&:distance)
    total_duration = trip_logs.sum(&:duration)
    max_speed = trip_logs.map(&:max_speed).compact.max || 0

    {
      total_trips: trip_logs.length,
      total_distance_km: (total_distance / 1000.0).round(2),
      total_duration_hours: (total_duration / 3600.0).round(2),
      avg_trip_distance_km: (total_distance / trip_logs.length / 1000.0).round(2),
      avg_trip_duration_minutes: (total_duration / trip_logs.length / 60.0).round(1),
      max_speed_kmh: (max_speed * 3.6).round(1)
    }
  end

  def default_summary
    {
      total_trips: 0,
      total_distance_km: 0,
      total_duration_hours: 0,
      avg_trip_distance_km: 0,
      avg_trip_duration_minutes: 0,
      max_speed_kmh: 0
    }
  end
end
