# frozen_string_literal: true

# app/models/concerns/waypoints/weather.rb
#
# Mixes weather data into Waypoint via the Weather:: service namespace.
# Automatically selects the right source based on how far out the date is:
#
#   Within 16 days  → Weather::Forecast (live Open-Meteo forecast)
#   Further out     → Weather::Historical (ERA5 30-yr climate normals)
#
# DB-backed via WeatherEstimate, keyed by (lat, lon, planned_date) — no
# foreign key to Waypoint. Multiple waypoints at the same location on the
# same date share a single WeatherEstimate row.
#
# == Usage
#
#   waypoint.weather                          # => Weather::Result or nil
#   waypoint.weather.description
#   waypoint.weather.forecast?
#   waypoint.weather.climate_normal?
#
#   waypoint.hourly_temperature(15)           # => 22.4 °C
#   waypoint.hourly_temperature(15, unit: :f) # => 72.3 °F
#   waypoint.hourly_temperatures              # => { 0 => 8.1, ..., 23 => 10.2 }
#
# == Batch prefetch
#
#   Waypoints::Weather.prefetch!(waypoints)
#   # Skips waypoints with a fresh WeatherEstimate. Fetches the rest and
#   # writes through. Waypoints sharing a location+date make one API call.
#
module Waypoints
  module Weather
    extend ActiveSupport::Concern

    included do
      # @return [Weather::Result, nil]
      def weather
        return @weather if defined?(@weather)

        @weather = fetch_weather
      end

      # @return [Weather::HourlyTemperature, nil]
      def hourly_temperature_curve
        return @hourly_temperature_curve if defined?(@hourly_temperature_curve)

        @hourly_temperature_curve = begin
          w    = weather
          date = planned_date
          return nil unless w && date && lonlat

          ::Weather::HourlyTemperature.new(w, solar_position(date))
        end
      end

      # Temperature at a specific hour on the planned date.
      # @param hour [Integer] 0–23
      # @param unit [Symbol]  :c or :f
      # @return [Float, nil]
      def hourly_temperature(hour, unit: :c)
        hourly_temperature_curve&.at(hour, unit: unit)
      end

      # Temperatures for all 24 hours on the planned date.
      # @param unit [Symbol] :c or :f
      # @return [Hash{Integer => Float}, nil]
      def hourly_temperatures(unit: :c)
        hourly_temperature_curve&.all(unit: unit)
      end
    end

    # Warm the DB for a collection of waypoints.
    # Waypoints sharing a (lat, lon, date) make only one API call between them.
    # Waypoints with a fresh WeatherEstimate are skipped entirely.
    #
    # @param waypoints [Array<Waypoint>]
    # @param client    [Weather::Client] injectable for testing
    def self.prefetch!(waypoints, client: ::Weather::Client.new)
      # Deduplicate by rounded (lat, lon, date) so co-located waypoints
      # on the same day only trigger one fetch.
      seen = Set.new

      waypoints.each do |wp|
        next unless wp.lonlat && wp.planned_date

        lat  = wp.lonlat.y.to_f.round(2)
        lon  = wp.lonlat.x.to_f.round(2)
        date = wp.planned_date
        key  = [lat, lon, date]

        next if seen.include?(key)

        seen << key

        # Skip if a fresh record already exists for this location+date
        existing = WeatherEstimate.for_location(lat, lon, date)
        next if existing&.fresh?

        result = service_for(lat, lon, date, client: client).fetch
        WeatherEstimate.store_result(result)
      rescue ::Weather::Forecast::HorizonError
        # Beyond forecast window — service_for guards this but be defensive
      rescue ::Weather::Client::Error => e
        Rails.logger.warn "[Waypoints::Weather] prefetch waypoint ##{wp.id}: #{e.message}"
      end
    end

    # Returns the appropriate service for a lat/lon/date combination.
    # Public so PrefetchWeatherJob and tests can call it directly.
    #
    # @return [Weather::Forecast | Weather::Historical]
    def self.service_for(lat, lon, date, client: ::Weather::Client.new)
      days_out = (date - Date.today).to_i

      if days_out <= ::Weather::Forecast::MAX_FORECAST_DAYS
        ::Weather::Forecast.new(lat: lat, lon: lon, date: date, client: client)
      else
        ::Weather::Historical.new(lat: lat, lon: lon, date: date, client: client)
      end
    end

    # The planned calendar date for this waypoint — derived from the inbound
    # route sequence. Falls back to trip start_on for the first waypoint.
    def planned_date
      return @planned_date if defined?(@planned_date)

      @planned_date = route_sequence&.date || trip&.start_on
    end

    private

    # Read from DB first by coordinate+date. Fetch from API on miss or stale
    # forecast, then write through to WeatherEstimate.
    def fetch_weather
      return nil unless lonlat
      return nil unless (date = planned_date)

      lat = lonlat.y.to_f.round(2)
      lon = lonlat.x.to_f.round(2)

      # 1. Fresh DB record — return immediately, no API call
      estimate = WeatherEstimate.for_location(lat, lon, date)
      return estimate.to_weather_result if estimate&.fresh?

      # 2. Miss or stale — fetch from API
      Rails.logger.debug "[Waypoints::Weather] waypoint ##{id}: fetching from API (#{lat}, #{lon}, #{date})"
      result = Waypoints::Weather.service_for(lat, lon, date).fetch

      # 3. Write through to DB
      WeatherEstimate.store_result(result)

      result
    rescue ::Weather::Client::Error => e
      Rails.logger.warn "[Waypoints::Weather] waypoint ##{id}: #{e.message}"
      # Serve stale data rather than nil if available
      WeatherEstimate.for_location(
        lonlat.y.to_f.round(2),
        lonlat.x.to_f.round(2),
        planned_date
      )&.to_weather_result
    end
  end
end
