# frozen_string_literal: true

require 'net/http'
require 'json'
require 'timeout'

module NetworkCoverage
  # Samples points along a TripTrack's stored geom (via TripTrackSampler),
  # then queries Claro Chile's ArcGIS FeatureServer at each point and
  # upserts any returned coverage polygons into NetworkCoverage::Feature
  # (provider: "claro").
  #
  # Chile runs on Esri ArcGIS Server (portalgisclarovtr.clarochile.cl), a
  # completely separate system from the GeoServer/WMS instance that serves
  # Argentina/Paraguay/Uruguay (see NetworkCoverage::ClaroFetcher). The upside:
  # ArcGIS's query endpoint supports a server-side buffered point query
  # directly (`distance` + `units` params), so there's no manual bbox math
  # needed the way WMS GetFeatureInfo requires — the server does the
  # buffering.
  #
  # Layer names map to FeatureServer sublayer indexes on the same service:
  #   0 => 2G, 1 => 3G, 2 => 4G, 3 => 5G
  #
  # Usage:
  #   chile = Boundary.find_by(name: "Chile")
  #   NetworkCoverage::ChileFetcher.new(trip_track: trip.trip_track, layer: "cobertura_movil_4G_CL", boundary: chile).call
  #
  class ChileFetcher
    PROVIDER = 'claro'
    FEATURE_SERVER_BASE = 'https://portalgisclarovtr.clarochile.cl/server2/rest/services/' \
                           'RedMovil_W/Cobertura_movil_Claro_AllCarriers_W/FeatureServer'
    LAYER_SUBLAYER_INDEX = {
      'cobertura_movil_2G_CL' => 0,
      'cobertura_movil_3G_CL' => 1,
      'cobertura_movil_4G_CL' => 2,
      'cobertura_movil_5G_CL' => 3
    }.freeze

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
      @sublayer_index = LAYER_SUBLAYER_INDEX.fetch(layer) do
        raise ArgumentError, "Unknown Chile layer #{layer.inspect}, expected one of #{LAYER_SUBLAYER_INDEX.keys}"
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

    attr_reader :trip_track, :layer, :boundary, :spacing_meters, :buffer_meters, :sublayer_index

    def points
      @points ||= TripTrackSampler.points_for(trip_track: trip_track, boundary: boundary,
                                              spacing_meters: spacing_meters)
    end

    def query_url
      "#{FEATURE_SERVER_BASE}/#{sublayer_index}/query"
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

    # ArcGIS's GeoJSON export sets a top-level "id" on each feature (usually
    # the OBJECTID), but fall back to common property names just in case a
    # given service configures it differently.
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
