# frozen_string_literal: true

require 'net/http'
require 'json'
require 'timeout'

module NetworkCoverage
  # Samples points along a TripTrack's stored geom (via TripTrackSampler),
  # then queries Claro Brazil's ArcGIS MapServer at each point and upserts
  # any returned coverage polygons into NetworkCoverage::Feature
  # (provider: "claro").
  #
  # Structurally similar to ChileFetcher (same ArcGIS query pattern,
  # buffered point query, GeoJSON response) but Brazil splits each
  # technology into its own separate MapServer service rather than
  # sublayers on one shared service:
  #
  #   https://cobertura.claro.com.br/arcgis/mapserver/Claro_4G_prd/MapServer/0/query
  #   https://cobertura.claro.com.br/arcgis/mapserver/Claro_5G_prd/MapServer/0/query
  #
  # Layer 0 on each service is confirmed to support Query (capabilities:
  # "Map,Query,Data") and geoJSON output, despite being a cached/tiled map
  # service for display purposes.
  #
  # Usage:
  #   sp = Boundary.find_unambiguous("São Paulo")
  #   NetworkCoverage::BrazilFetcher.new(trip_track: trip.trip_track, layer: "cobertura_movel_4G_BR", boundary: sp).call
  #
  class BrazilFetcher
    PROVIDER = 'claro'
    BASE = 'https://cobertura.claro.com.br/arcgis/mapserver'
    LAYER_SERVICE_NAME = {
      'cobertura_movel_4G_BR' => 'Claro_4G_prd',
      'cobertura_movel_5G_BR' => 'Claro_5G_prd'
    }.freeze
    SUBLAYER_INDEX = 0

    SPACING_METERS = 1000
    BUFFER_METERS = 500
    REQUEST_DELAY = 0.2
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 10
    HARD_TIMEOUT = 20
    MAX_RETRIES = 2

    def initialize(trip_track:, layer:, boundary: nil, spacing_meters: SPACING_METERS, buffer_meters: BUFFER_METERS)
      @trip_track = trip_track
      @layer = layer
      @boundary = boundary
      @spacing_meters = spacing_meters
      @buffer_meters = buffer_meters
      @service_name = LAYER_SERVICE_NAME.fetch(layer) do
        raise ArgumentError, "Unknown Brazil layer #{layer.inspect}, expected one of #{LAYER_SERVICE_NAME.keys}"
      end
    end

    def call
      skipped = 0
      points.each_with_index do |(lon, lat), i|
        if Feature.covers_point?(trip: trip_track.trip, provider: PROVIDER, layer: layer, lon: lon, lat: lat)
          skipped += 1
        else
          features = fetch_features(lon, lat)
          features.each { |f| upsert_feature(f) }
          sleep(REQUEST_DELAY)
        end
        yield(i + 1, points.size, skipped) if block_given?
      end
    end

    private

    attr_reader :trip_track, :layer, :boundary, :spacing_meters, :buffer_meters, :service_name

    def points
      @points ||= TripTrackSampler.points_for(trip_track: trip_track, boundary: boundary,
                                              spacing_meters: spacing_meters)
    end

    def query_url
      "#{BASE}/#{service_name}/MapServer/#{SUBLAYER_INDEX}/query"
    end

    def fetch_features(lon, lat, attempt: 0)
      geometry = { x: lon, y: lat, spatialReference: { wkid: 4326 } }.to_json

      params = URI.encode_www_form(
        geometry: geometry,
        geometryType: 'esriGeometryPoint',
        inSR: 4326,
        distance: buffer_meters,
        units: 'esriSRUnit_Meter',
        spatialRel: 'esriSpatialRelIntersects',
        outFields: '*',
        f: 'geojson'
      )

      uri = URI(query_url)

      body = Timeout.timeout(HARD_TIMEOUT, Timeout::Error, "hard timeout at #{lon},#{lat}") do
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.open_timeout = OPEN_TIMEOUT
        http.read_timeout = READ_TIMEOUT
        response = http.get("#{uri.path}?#{params}")
        response.is_a?(Net::HTTPSuccess) ? response.body : nil
      end

      return [] if body.nil?

      parsed = JSON.parse(body)
      if parsed['error']
        warn "  [error] #{lon},#{lat}: #{parsed['error']['message']}"
        return []
      end

      parsed['features'] || []
    rescue JSON::ParserError
      []
    rescue Timeout::Error, Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET, Errno::ETIMEDOUT, SocketError,
           EOFError => e
      if attempt < MAX_RETRIES
        warn "  [retry] #{lon},#{lat} (#{e.class}: #{e.message}), attempt #{attempt + 1}"
        sleep(1 + attempt)
        fetch_features(lon, lat, attempt: attempt + 1)
      else
        warn "  [skip] #{lon},#{lat} failed after #{MAX_RETRIES} retries: #{e.class}: #{e.message}"
        []
      end
    end

    def feature_source_id(feature)
      feature['id'] ||
        feature.dig('properties', 'OBJECTID') ||
        feature.dig('properties', 'FID') ||
        feature.dig('properties', 'ObjectId')
    end

    def upsert_feature(feature)
      source_id = feature_source_id(feature)
      if source_id.nil?
        warn '  [warn] feature with no identifiable id, skipping to avoid duplicate rows on rerun'
        return
      end

      Feature.upsert_from_geojson!(
        trip: trip_track.trip,
        provider: PROVIDER,
        layer: layer,
        source_feature_id: source_id.to_s,
        geojson_geometry: feature['geometry']
      )
    end
  end
end
