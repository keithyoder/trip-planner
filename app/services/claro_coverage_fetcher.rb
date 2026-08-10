# frozen_string_literal: true

require 'net/http'
require 'json'
require 'timeout'

# Samples points every N meters along a TripTrack's stored geom (using
# PostGIS itself to do the distance-along-line math, not Ruby), then queries
# Claro's WMS GetFeatureInfo endpoint at each point and upserts any returned
# coverage polygons into CoverageFeature (provider: "claro").
#
# Pass `boundary:` to clip the trip track to a single country/region BEFORE
# sampling — critical for a multi-country trip, since without it every
# sample point across the entire route gets queried against a single
# country's layer, wasting thousands of requests on points that were never
# going to return anything.
#
# trip_tracks.geom is a MultiLineString with Z. Each component line
# (post-clip) is dumped and interpolated separately (spacing computed
# per-segment, in a metric projection) so spacing stays consistent even
# where the track is made of several disjoint pieces.
#
# Usage:
#   uruguay = Boundary.find_by(name: "Uruguay")
#   ClaroCoverageFetcher.new(trip_track: trip.trip_track, layer: "cobertura_externa_4G_UY", boundary: uruguay).call
#
class ClaroCoverageFetcher
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
    points.each_with_index do |(lon, lat), i|
      features = fetch_features(lon, lat)
      features.each { |f| upsert_feature(f) }
      sleep(REQUEST_DELAY)
      yield(i + 1, points.size) if block_given?
    end
  end

  private

  attr_reader :trip_track, :layer, :boundary, :spacing_meters, :bbox_half_width_meters

  # Clips the trip track to `boundary` (if given), dumps each resulting
  # component line, projects to 3857 for metric spacing, interpolates points
  # every `spacing_meters` along each component independently, then
  # transforms back to 4326.
  #
  # @return [Array<[Float, Float]>] array of [lon, lat]
  def points
    @points ||= begin
      sql = <<~SQL
        WITH base AS (
          #{base_geom_sql}
        ),
        segments AS (
          SELECT (ST_Dump(ST_Transform(base.clipped, 3857))).geom AS seg
          FROM base
        ),
        line_segments AS (
          SELECT seg FROM segments WHERE GeometryType(seg) = 'LINESTRING'
        ),
        sampled AS (
          SELECT (ST_Dump(
            ST_LineInterpolatePoints(
              seg,
              LEAST(1.0, GREATEST(0.0001, #{spacing_meters} / ST_Length(seg)))
            )
          )).geom AS pt
          FROM line_segments
          WHERE ST_Length(seg) > 0
        )
        SELECT ST_AsGeoJSON(ST_Transform(pt, 4326)) AS pt FROM sampled
      SQL

      ActiveRecord::Base.connection.select_all(sql).map do |row|
        JSON.parse(row['pt'])['coordinates']
      end
    end
  end

  # Builds the CTE that produces the (optionally boundary-clipped) 2D
  # geometry to sample from. Joins to `boundaries` by id rather than
  # inlining WKT so large country polygons don't get embedded as literal
  # SQL text.
  def base_geom_sql
    if boundary
      <<~SQL
        SELECT ST_Intersection(ST_Force2D(tt.geom::geometry), b.geom::geometry) AS clipped
        FROM trip_tracks tt, boundaries b
        WHERE tt.trip_id = #{trip_track.trip_id} AND b.id = #{boundary.id}
      SQL
    else
      <<~SQL
        SELECT ST_Force2D(tt.geom::geometry) AS clipped
        FROM trip_tracks tt
        WHERE tt.trip_id = #{trip_track.trip_id}
      SQL
    end
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
    CoverageFeature.upsert_from_geojson!(
      trip: trip_track.trip,
      provider: PROVIDER,
      layer: layer,
      source_feature_id: feature['id'],
      geojson_geometry: feature['geometry']
    )
  end
end
