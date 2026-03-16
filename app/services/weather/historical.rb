# frozen_string_literal: true

# app/services/weather/historical.rb
#
# Fetches historical climate normals from Open-Meteo's ERA5 reanalysis dataset
# for a given location and date. Returns multi-year averages for the same
# calendar day — a statistical "what to expect" rather than a live forecast.
#
# HTTP is delegated to Weather::Client. This service handles year iteration,
# averaging, standard deviation, and caching.
#
# == Usage
#
#   service = Weather::Historical.new(lat: -22.9, lon: -43.1, date: Date.new(2026, 11, 15))
#   result  = service.fetch   # => Weather::Result
#
# == Caching
#
#   Results cached in Rails.cache keyed to lat/lon/month-day (not year), 7-day TTL.
#   Climate normals never change, so long TTLs are appropriate. The WeatherEstimate
#   DB table is the authoritative long-term store; the cache warms it on first fetch.
#
module Weather
  class Historical
    # ERA5 data through 2024; 1991 is the WMO climate normal period start.
    CLIMATE_START_YEAR = 1991
    CLIMATE_END_YEAR   = 2024

    VARIABLES = %w[
      temperature_2m_mean
      temperature_2m_max
      temperature_2m_min
      precipitation_sum
      windspeed_10m_mean
      windspeed_10m_max
      relative_humidity_2m_mean
    ].freeze

    class FetchError < Weather::Client::Error; end

    # @param lat    [Float]          latitude  (positive = north)
    # @param lon    [Float]          longitude (positive = east)
    # @param date   [Date]           the planned calendar date
    # @param client [Weather::Client] injectable for testing
    def initialize(lat:, lon:, date:, client: Weather::Client.new)
      # ERA5 native resolution is 0.25° (~28km) — 2dp gives ~1km precision,
      # well within the grid, and improves cache hit rates for nearby locations.
      @lat    = lat.to_f.round(2)
      @lon    = lon.to_f.round(2)
      @date   = date
      @client = client
    end

    # @return [Weather::Result]
    def fetch
      Rails.cache.fetch(cache_key, expires_in: 7.days) do
        parse(accumulate_years)
      end
    end

    private

    # Request each year in the climate normal period and accumulate per-variable
    # arrays for statistical aggregation. Years where the date doesn't exist
    # (Feb 29 on non-leap years) or where the API fails are silently skipped.
    def accumulate_years
      daily_values = Hash.new { |h, k| h[k] = [] }

      CLIMATE_START_YEAR.upto(CLIMATE_END_YEAR) do |year|
        target = Date.new(year, @date.month, @date.day)

        data = @client.climate(
          latitude: @lat,
          longitude: @lon,
          start_date: target.strftime('%Y-%m-%d'),
          end_date: target.strftime('%Y-%m-%d'),
          daily: VARIABLES.join(',')
        )

        VARIABLES.each do |var|
          value = data.dig('daily', var, 0)
          daily_values[var] << value.to_f unless value.nil?
        end
      rescue ArgumentError
        next # Feb 29 on non-leap year
      rescue Weather::Client::Error => e
        Rails.logger.warn "[Weather::Historical] skipping #{year}: #{e.message}"
        next
      end

      raise FetchError, "No climate data returned for #{@lat},#{@lon} on #{@date}" if daily_values.empty?

      daily_values
    end

    def parse(daily_values)
      avg = ->(key) { mean(daily_values[key]) }
      sd  = ->(key) { std_dev(daily_values[key]) }

      # Helper to wrap a float in Units::Temperature (celsius)
      temp = ->(key) { (v = avg.call(key)) && Units::Temperature.new(v, units: :celsius) }

      # Helper to wrap a float in Units::Speed (km_per_hour → stored as base m/s)
      speed = ->(key) { (v = avg.call(key)) && Units::Speed.new(v, units: :km_per_hour) }

      Weather::Result.new(
        lat: @lat,
        lon: @lon,
        date: @date,
        source: :climate_normal,
        temp_mean: temp.call('temperature_2m_mean'),
        temp_min: temp.call('temperature_2m_min'),
        temp_max: temp.call('temperature_2m_max'),
        temp_min_std: sd.call('temperature_2m_min')&.round(1),
        temp_max_std: sd.call('temperature_2m_max')&.round(1),
        precipitation_mm: avg.call('precipitation_sum')&.round(2),
        precipitation_std: sd.call('precipitation_sum')&.round(2),
        precipitation_years: daily_values['precipitation_sum'].dup,
        windspeed: speed.call('windspeed_10m_mean'),
        windspeed_std: sd.call('windspeed_10m_mean')&.round(1),
        windspeed_max: speed.call('windspeed_10m_max'),
        windspeed_max_std: sd.call('windspeed_10m_max')&.round(1),
        humidity_pct: avg.call('relative_humidity_2m_mean')&.round(0)&.to_i
      )
    end

    def mean(values)
      return nil if values.empty?

      values.sum / values.size.to_f
    end

    # Sample standard deviation (Bessel's correction — divides by n-1)
    def std_dev(values)
      return nil if values.size < 2

      m = values.sum / values.size.to_f
      Math.sqrt(values.sum { |v| (v - m)**2 } / (values.size - 1).to_f)
    end

    # Keyed to rounded coordinates and month+day (not year). Coordinates are
    # rounded to 2dp (~1km) — nearby locations in the same town share a cache entry.
    def cache_key
      "weather/historical/#{@lat}/#{@lon}/#{@date.strftime('%m-%d')}"
    end
  end
end
