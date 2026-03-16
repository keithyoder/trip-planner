# frozen_string_literal: true

# app/services/weather/forecast.rb
#
# Fetches real weather forecasts from Open-Meteo's forecast endpoint.
# Use this when the date is within MAX_FORECAST_DAYS. Beyond that, fall
# back to Weather::Historical.
#
# Returns a Weather::Result with source: :forecast. The struct is identical
# to what Weather::Historical returns, so views are source-agnostic.
#
# == Usage
#
#   service = Weather::Forecast.new(lat: -22.9, lon: -43.1, date: Date.today + 5)
#   result  = service.fetch   # => Weather::Result
#   result.forecast?          # => true
#
# == Horizon guard
#
#   Requesting a date beyond MAX_FORECAST_DAYS raises Weather::Forecast::HorizonError.
#   The Waypoints::Weather concern rescues this and falls back to Weather::Historical.
#
module Weather
  class Forecast
    MAX_FORECAST_DAYS = 16
    CACHE_TTL         = 3.hours

    VARIABLES = %w[
      temperature_2m_mean
      temperature_2m_max
      temperature_2m_min
      precipitation_sum
      precipitation_hours
      precipitation_probability_max
      windspeed_10m_mean
      windspeed_10m_max
      relative_humidity_2m_mean
      weathercode
    ].freeze

    class HorizonError < StandardError; end
    class FetchError   < Weather::Client::Error; end

    # @param lat    [Float]          latitude
    # @param lon    [Float]          longitude
    # @param date   [Date]           the planned date
    # @param client [Weather::Client] injectable for testing
    def initialize(lat:, lon:, date:, client: Weather::Client.new)
      # Best-match forecast model for South America is ~0.1° (~11km) — 2dp
      # gives ~1km precision, well within the grid.
      @lat    = lat.to_f.round(2)
      @lon    = lon.to_f.round(2)
      @date   = date
      @client = client
    end

    # @return [Weather::Result]
    # @raise  [HorizonError] if the date is beyond the forecast window
    def fetch
      days_out = (@date - Date.today).to_i
      if days_out > MAX_FORECAST_DAYS
        raise HorizonError,
              "#{@date} is #{days_out} days out — beyond the #{MAX_FORECAST_DAYS}-day forecast horizon"
      end

      Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) do
        parse(@client.forecast(request_params))
      end
    end

    private

    def request_params
      {
        latitude: @lat,
        longitude: @lon,
        start_date: @date.strftime('%Y-%m-%d'),
        end_date: @date.strftime('%Y-%m-%d'),
        daily: VARIABLES,
        models: 'best_match'
      }
    end

    def parse(data)
      daily = data['daily'] || {}
      raise FetchError, "No forecast data for #{@lat},#{@lon} on #{@date}" if daily.empty?

      temp  = ->(key) { (v = daily[key]&.first) && Units::Temperature.new(v, units: :celsius) }
      speed = ->(key) { (v = daily[key]&.first) && Units::Speed.new(v, units: :km_per_hour) }

      Weather::Result.new(
        lat: @lat,
        lon: @lon,
        date: @date,
        source: :forecast,
        temp_mean: temp.call('temperature_2m_mean'),
        temp_min: temp.call('temperature_2m_min'),
        temp_max: temp.call('temperature_2m_max'),
        temp_min_std: nil,
        temp_max_std: nil,
        precipitation_mm: daily['precipitation_sum']&.first&.then { |v| v.round(2) },
        precipitation_hours: daily['precipitation_hours']&.first&.then { |v| v.round(0).to_i },
        precipitation_probability_max: daily['precipitation_probability_max']&.first&.then { |v| v.round(0).to_i },
        windspeed: speed.call('windspeed_10m_mean'),
        windspeed_max: speed.call('windspeed_10m_max'),
        humidity_pct: daily['relative_humidity_2m_mean']&.first&.then { |v| v.round(0).to_i },
        cloudcover_pct: nil,
        weathercode: daily['weathercode']&.first&.then { |v| v.round(0).to_i }
      )
    end

    def cache_key
      "weather/forecast/#{@lat}/#{@lon}/#{@date.strftime('%Y-%m-%d')}"
    end
  end
end
