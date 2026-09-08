# frozen_string_literal: true

class DashboardController < ApplicationController
  layout 'welcome'

  def index
    respond_to do |format|
      format.html do
        # data loaded asynchronously via JavaScript
      end

      format.json do
        latest_log = TelemetryLog.with_gps.recent.first

        if latest_log.nil?
          render json: { error: 'No telemetry data available' }, status: :not_found
          return
        end

        trip_detector = TripDetector.instance
        trip_detector.todays_trips
        today_distance = calculate_today_distance(trip_detector)

        data = Dashboard::DataPresenter.new(
          latest_log,
          trip_detector: trip_detector,
          today_distance: today_distance
        ).as_json

        data[:trip_points] = trip_detector.currently_travelling? ? trip_detector.current_trip_points : []

        todays_trip_logs = TripLog.today.recent.to_a
        summary = TripLog.summary_for(todays_trip_logs)
        fuel_used = TelemetryLog.total_fuel_used(todays_trip_logs)
        summary_presenter = TripLogs::DaySummaryPresenter.new(summary, fuel_used)

        data[:todays_trips] = {
          trips: todays_trip_logs.map { |trip_log| format_trip_log(trip_log) },
          summary: {
            total_trips: summary[:total_trips],
            distance: summary_presenter.distance,
            duration: summary_presenter.duration,
            max_speed: summary_presenter.max_speed,
            fuel_used: summary_presenter.fuel_used,
            fuel_efficiency: summary_presenter.fuel_efficiency
          }
        }

        render json: data
      end
    end
  end

  def todays_trips
    trip_detector = TripDetector.instance
    trips = trip_detector.todays_trips

    render json: {
      trips: trips.map { |t| format_trip(t) },
      summary: trip_detector.trip_summary(trips)
    }
  end

  private

  def calculate_today_distance(trip_detector)
    distance_meters = TripLog.today.to_a.sum { |trip| trip.distance.to_f }
    distance_meters += trip_detector.current_trip[:total_distance] if trip_detector.current_trip
    Units::Distance.new(distance_meters)
  end

  def format_trip_log(trip_log)
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
      coordinates: trip_log.coordinates.map { |coord| [coord[1], coord[0]] }
    }
  end
end
