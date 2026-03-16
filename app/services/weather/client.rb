# frozen_string_literal: true

require 'net/http'
require 'json'

# app/services/weather/client.rb
#
# Shared HTTP client for the Open-Meteo API family. Handles connection
# management, timeouts, error normalisation, and response parsing so that
# individual weather services (Weather::Historical, Weather::Forecast) don't
# repeat that boilerplate.
#
# Open-Meteo is free and requires no API key for the standard endpoints.
# The commercial API is supported via the optional +api_key+ argument.
#
# == Usage
#
#   client = Weather::Client.new
#   client.climate(latitude: -22.9, longitude: -43.1, ...)
#   client.forecast(latitude: -22.9, longitude: -43.1, ...)
#
module Weather
  class Client
    FORECAST_BASE = 'https://api.open-meteo.com'
    CLIMATE_BASE  = 'https://climate-api.open-meteo.com'

    OPEN_TIMEOUT = 5   # seconds to establish TCP connection
    READ_TIMEOUT = 15  # seconds to wait for response body

    class Error < StandardError; end

    # @param api_key [String, nil] optional commercial API key
    def initialize(api_key: nil)
      @api_key = api_key
    end

    # Fetch from the ERA5 climate reanalysis endpoint.
    # Used for historical normals when the trip is months away.
    #
    # @param params [Hash] Open-Meteo query parameters
    # @return [Hash] parsed JSON response
    def climate(params)
      get(CLIMATE_BASE, '/v1/climate', params)
    end

    # Fetch from the live forecast endpoint.
    # Supports up to 16 days ahead.
    #
    # @param params [Hash] Open-Meteo query parameters
    # @return [Hash] parsed JSON response
    def forecast(params)
      get(FORECAST_BASE, '/v1/forecast', params)
    end

    private

    def get(base, path, params)
      uri = URI("#{base}#{path}")
      uri.query = encode_params(merged_params(params))

      Rails.logger.debug "[Weather::Client] GET #{uri}"

      response = Net::HTTP.start(
        uri.host, uri.port,
        use_ssl: true,
        open_timeout: OPEN_TIMEOUT,
        read_timeout: READ_TIMEOUT
      ) do |http|
        http.get(uri.request_uri, 'Accept' => 'application/json')
      end

      handle_response(response)
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      raise Error, "Open-Meteo request timed out: #{e.message}"
    rescue Errno::ECONNREFUSED, SocketError => e
      raise Error, "Open-Meteo connection failed: #{e.message}"
    end

    def handle_response(response)
      unless response.is_a?(Net::HTTPSuccess)
        raise Error, "Open-Meteo returned HTTP #{response.code}: #{response.body.truncate(200)}"
      end

      body = JSON.parse(response.body)

      # Open-Meteo signals application-level errors with a "reason" key on 200s
      raise Error, "Open-Meteo error: #{body['reason'] || 'unknown'}" if body['error']

      body
    rescue JSON::ParserError => e
      raise Error, "Open-Meteo returned invalid JSON: #{e.message}"
    end

    def merged_params(params)
      base = { timezone: 'auto' }
      base[:apikey] = @api_key if @api_key
      base.merge(params)
    end

    # Build a query string that expands Array values into repeated keys:
    #   { daily: ['a', 'b'] } => "daily=a&daily=b"
    # This is required by Open-Meteo — a comma-joined string is not accepted.
    def encode_params(params)
      params.flat_map do |key, value|
        if value.is_a?(Array)
          value.map { |v| "#{URI.encode_www_form_component(key)}=#{URI.encode_www_form_component(v)}" }
        else
          ["#{URI.encode_www_form_component(key)}=#{URI.encode_www_form_component(value)}"]
        end
      end.join('&')
    end
  end
end
