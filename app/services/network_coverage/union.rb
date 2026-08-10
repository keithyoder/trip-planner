# frozen_string_literal: true

require 'json'

module NetworkCoverage
  # Builds a simplified coverage polygon by buffering the trip track (or a
  # boundary-clipped portion of it) by a fixed distance, then intersecting
  # that buffered corridor with the union of fetched NetworkCoverage::Feature
  # polygons for a given provider/layer.
  #
  # Why: coverage polygons returned by providers (Claro's WMS/ArcGIS
  # services) are often huge — a single fetched feature can cover an entire
  # region or country, most of which is nowhere near the actual route.
  # Storing/analyzing hundreds of those raw, overlapping shapes is wasteful.
  # Clipping to a narrow corridor around the route keeps only the part of
  # the coverage that's actually relevant to the trip, which is both a much
  # simpler geometry to store and cheaper to intersect against later.
  #
  # Usage:
  #   uruguay = Boundary.find_by(name: "Uruguay")
  #   result = NetworkCoverage::Union.new(
  #     trip_track: trip.trip_track,
  #     provider: "claro",
  #     layer: "cobertura_externa_4G_UY",
  #     boundary: uruguay,
  #     buffer_meters: 1000
  #   ).call
  #   result # => RGeo geometry, or nil if nothing to union
  #
  class Union
    DEFAULT_BUFFER_METERS = 1000

    def initialize(trip_track:, provider:, layer:, boundary: nil, buffer_meters: DEFAULT_BUFFER_METERS)
      @trip_track = trip_track
      @provider = provider
      @layer = layer
      @boundary = boundary
      @buffer_meters = buffer_meters
    end

    # @return [RGeo::Feature::Geometry, nil]
    def call
      geojson = geojson_string
      return nil if geojson.nil?

      RGeo::GeoJSON.decode(geojson)
    end

    # @return [Hash] a GeoJSON Feature hash, ready to write to a file
    def to_geojson_feature
      geojson = geojson_string
      {
        type: 'Feature',
        geometry: geojson.nil? ? nil : JSON.parse(geojson),
        properties: {
          trip_id: trip_track.trip_id,
          provider: provider,
          layer: layer,
          boundary: boundary&.name,
          buffer_meters: buffer_meters,
          feature_count: feature_count
        }
      }
    end

    private

    attr_reader :trip_track, :provider, :layer, :boundary, :buffer_meters

    def geojson_string
      geom_sql = corridor_sql
      connection.select_value(<<~SQL)
        SELECT ST_AsGeoJSON(
          #{Feature.clipped_union_sql(geom_sql, trip_id: trip_track.trip_id, provider: provider, layer: layer)}
        )
      SQL
    end

    def feature_count
      Feature.where(trip_id: trip_track.trip_id, provider: provider, layer: layer).count
    end

    # The buffered corridor around the (optionally boundary-clipped) trip
    # track. Buffering is done in EPSG:3857 (planar) rather than via
    # ::geography (true geodesic) — geodesic buffering is noticeably slower
    # for large/complex line geometries, and at a 1000m buffer width the
    # distortion from planar buffering is negligible even at high southern
    # latitudes (Patagonia/Tierra del Fuego). If buffer_meters gets much
    # larger, or the route approaches the poles, geography buffering would
    # be worth reconsidering for accuracy.
    def corridor_sql
      <<~SQL
        SELECT ST_Transform(
          ST_Buffer(ST_Transform((#{base_geom_sql}), 3857), #{buffer_meters}),
          4326
        )
      SQL
    end

    def base_geom_sql
      if boundary
        <<~SQL
          SELECT ST_Intersection(ST_Force2D(tt.geom::geometry), b.geom::geometry)
          FROM trip_tracks tt, boundaries b
          WHERE tt.trip_id = #{trip_track.trip_id} AND b.id = #{boundary.id}
        SQL
      else
        <<~SQL
          SELECT ST_Force2D(tt.geom::geometry)
          FROM trip_tracks tt
          WHERE tt.trip_id = #{trip_track.trip_id}
        SQL
      end
    end

    def connection
      ActiveRecord::Base.connection
    end
  end
end
