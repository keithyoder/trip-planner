# frozen_string_literal: true

require 'heading_calculator'

module DashboardDataBuilder
  extend ActiveSupport::Concern
  include HeadingCalculator

  def build_dashboard_data(log, trip_detector: nil, today_distance: 0) # rubocop:disable Metrics/MethodLength,Metrics/AbcSize
    return nil unless log

    gps_data = extract_gps_data(log)

    {
      travelling: trip_detector&.currently_travelling? || false,
      distance_km: today_distance.km.round(1),
      speed_kmh: calculate_speed(log.data['gps_speed']),
      gps: gps_data,
      device: log.data['device'], # "ios" or whatever the Pi sends
      transport_mode: log.data['ios_activity'], # nil for Pi-sourced logs
      temperature: log.data['shtc3_temperature']&.round(1),
      weather: extract_weather_data(log),
      timestamp: log.timestamp.iso8601
    }
  end

  private

  def extract_gps_data(log) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity
    {
      lat: log.data['gps_latitude']&.to_f,
      lon: log.data['gps_longitude']&.to_f,
      altitude: log.data['gps_altitude']&.to_f,
      heading: log.data['gps_heading']&.to_f,
      direction: heading_to_direction(log.data['gps_heading']&.to_f),
      climb: log.data['gps_climb']&.to_f,
      satellites: log.data['gps_satellites']&.to_i
    }
  end

  def extract_weather_data(log)
    {
      temperature: log.data['shtc3_temperature']&.round(1),
      humidity: log.data['shtc3_humidity']&.round(1),
      pressure: log.data['bmp581_pressure']&.round(1),
      dewpoint: log.data['shtc3_dewpoint']&.round(1)
    }
  end

  def calculate_speed(gps_speed)
    return 0 unless gps_speed

    (gps_speed.to_f * 3.6).round(1)
  end
end
