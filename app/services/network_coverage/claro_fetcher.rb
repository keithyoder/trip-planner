# frozen_string_literal: true

require 'net/http'
require 'json'
require 'timeout'

module NetworkCoverage
  # Samples points along a TripTrack's stored geom (via TripTrackSampler),
  # then queries Claro's WMS GetFeatureInfo endpoint at each point and
  # upserts any returned coverage polygons into NetworkCoverage::Feature
  # (provider: "claro").
  #
  # Covers Argentina, Paraguay, and Uruguay, which are all served from the
  # same GeoServer instance. Chile is a separate system — see
  # NetworkCoverage::ChileFetcher.
  #
  # Pass `boundary:` to clip the trip track to a single country/region
  # BEFORE sampling — critical for a multi-country trip, since without it
  # every sample point across the entire route gets queried against a
  # single country's layer, wasting thousands of requests on points that
  # were never going to return anything.
  #
  # Usage:
  #   uruguay = Boundary.find_by(name: "Uruguay")
  #   NetworkCoverage::ClaroFetcher.new(trip_track: trip.trip_track, layer: "cobertura_externa_4G_UY", boundary: uruguay).call
  #
  class ClaroFetcher
    PROVIDER = 'claro'
    WMS_BASE = 'https://clarovm.trafficmanager.net/geoserver/claro_argentina-coverage-production/wms'
    SPACING_METERS = 1000
    BBOX_HALF_WIDTH_METERS = 500
    REQUEST_DELAY = 0.2 # seconds, be polite to the server
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 10
    HARD_TIMEOUT = 20 # absolute ceiling per request, regardless of where it's stuck
    MAX_RETRIES = 2

    def initialize(trip_track:, layer:, boundary: nil, spacing_meters: SPACING_METERS,
                   bbox_half_width_meters: BBOX_HALF_WIDTH_METERS)
      @trip_track = trip_track
      @layer = layer
      @boundary = boundary
      @spacing_meters = spacing_meters
      @bbox_half_width_meters = bbox_half_width_meters
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

    attr_reader :trip_track, :layer, :boundary, :spacing_meters, :bbox_half_width_meters

    def points
      @points ||= NetworkCoverage::TripTrackSampler.points_for(trip_track: trip_track, boundary: boundary,
                                                               spacing_meters: spacing_meters)
    end

    def fetch_features(lon, lat, attempt: 0)
      lat_deg = bbox_half_width_meters / 111_320.0
      lon_deg = bbox_half_width_meters / (111_320.0 * Math.cos(lat * Math::PI / 180))
      bbox = "#{lon - lon_deg},#{lat - lat_deg},#{lon + lon_deg},#{lat + lat_deg}"

      uri = URI(WMS_BASE)
      uri.query = URI.encode_www_form(
        service: 'WMS',
        version: '1.1.0',
        request: 'GetFeatureInfo',
        layers: "claro_argentina-coverage-production:#{layer}",
        query_layers: "claro_argentina-coverage-production:#{layer}",
        srs: 'EPSG:4326',
        bbox: bbox,
        width: 101,
        height: 101,
        x: 50,
        y: 50,
        info_format: 'application/json'
      )

      body = Timeout.timeout(HARD_TIMEOUT, Timeout::Error, "hard timeout at #{lon},#{lat}") do
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.open_timeout = OPEN_TIMEOUT
        http.read_timeout = READ_TIMEOUT
        response = http.get("#{uri.path}?#{uri.query}")
        response.is_a?(Net::HTTPSuccess) ? response.body : nil
      end

      return [] if body.nil?

      JSON.parse(body)['features'] || []
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

    def upsert_feature(feature)
      Feature.upsert_from_geojson!(
        trip: trip_track.trip,
        provider: PROVIDER,
        layer: layer,
        source_feature_id: feature['id'],
        geojson_geometry: feature['geometry']
      )
    end
  end
end
