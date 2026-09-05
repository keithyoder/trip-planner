# frozen_string_literal: true

require 'json'

module NetworkCoverage
  # Builds a simplified coverage polygon by buffering a source line (either
  # a whole trip's track, or a single route's own line) by a fixed
  # distance, then intersecting that buffered corridor with the union of
  # fetched NetworkCoverage::Feature polygons for a given provider/layer.
  # Pass exactly one of trip_track: or route: to pick which source line to
  # buffer -- feature lookup (the raw carrier polygons unioned against the
  # corridor) is always trip-wide either way, since those are fetched once
  # per trip/provider/layer regardless of which corridor they're being
  # clipped against.
  #
  # Why buffer+clip at all: coverage polygons returned by providers (Claro's
  # WMS/ArcGIS services) are often huge — a single fetched feature can cover
  # an entire region or country, most of which is nowhere near the actual
  # route. Storing/analyzing hundreds of those raw, overlapping shapes is
  # wasteful. Clipping to a narrow corridor around the route keeps only the
  # part of the coverage that's actually relevant to the trip, which is both
  # a much simpler geometry to store and cheaper to intersect against later.
  #
  # Why trip_track: vs route: matters: a trip_track: corridor spans the
  # whole multi-country trip, which is appropriate for a one-off export
  # (see lib/tasks/coverage.rake) but far more geometry than any single
  # day's map needs. route: scopes the corridor down to just that route's
  # own line, which is what NetworkCoverage::RouteCoverageBuilder uses for
  # both the printed day-plan PDF and the live per-route map overlay.
  #
  # Usage (whole trip):
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
  # Usage (single route):
  #   result = NetworkCoverage::Union.new(
  #     route: route,
  #     provider: "claro",
  #     layer: "cobertura_movel_4G_BR",
  #     boundary: brasil
  #   ).call
  #
  class Union
    DEFAULT_BUFFER_METERS = 1000

    # @param provider [String] e.g. "claro"
    # @param layer [String] e.g. "cobertura_externa_4G_UY"
    # @param trip_track [TripTrack, nil] buffer the whole trip's track --
    #   pass exactly one of trip_track: or route:
    # @param route [Route, nil] buffer just this route's own line
    # @param boundary [Boundary, nil] optionally clip the source line to a
    #   single country/boundary before buffering
    # @param buffer_meters [Integer] corridor half-width in meters
    def initialize(provider:, layer:, trip_track: nil, route: nil, boundary: nil, buffer_meters: DEFAULT_BUFFER_METERS)
      raise ArgumentError, 'Union requires exactly one of trip_track: or route:' if trip_track.nil? == route.nil?

      @trip_track = trip_track
      @route = route
      @provider = provider
      @layer = layer
      @boundary = boundary
      @buffer_meters = buffer_meters
    end

    # @return [RGeo::Feature::Geometry, nil] nil if nothing to union (no
    #   fetched features overlap the corridor)
    def call
      geojson = geojson_string
      return nil if geojson.nil?

      RGeo::GeoJSON.decode(geojson)
    end

    # @return [Hash] a GeoJSON Feature hash, ready to write to a file or
    #   serve as a JSON API response. `geometry` is nil under the same
    #   condition #call returns nil.
    def to_geojson_feature
      geojson = geojson_string
      {
        type: 'Feature',
        geometry: geojson.nil? ? nil : JSON.parse(geojson),
        properties: {
          trip_id: trip_id,
          route_id: route&.id,
          provider: provider,
          layer: layer,
          boundary: boundary&.name,
          buffer_meters: buffer_meters,
          feature_count: feature_count
        }
      }
    end

    private

    attr_reader :trip_track, :route, :provider, :layer, :boundary, :buffer_meters

    def trip_id
      trip_track&.trip_id || route.trip_id
    end

    def geojson_string
      geom_sql = corridor_sql
      connection.select_value(<<~SQL)
        SELECT ST_AsGeoJSON(
          #{Feature.clipped_union_sql(geom_sql, trip_id: trip_id, provider: provider, layer: layer)}
        )
      SQL
    end

    def feature_count
      Feature.where(trip_id: trip_id, provider: provider, layer: layer).count
    end

    # Buffering is done in EPSG:3857 (planar) rather than via ::geography
    # (true geodesic) — geodesic buffering is noticeably slower for
    # large/complex line geometries, and at a 1000m buffer width the
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
          SELECT ST_Intersection(ST_Force2D(g.geom::geometry), b.geom::geometry)
          FROM (#{scope_geom_sql}) AS g(geom), boundaries b
          WHERE b.id = #{boundary.id}
        SQL
      else
        <<~SQL
          SELECT ST_Force2D(g.geom::geometry)
          FROM (#{scope_geom_sql}) AS g(geom)
        SQL
      end
    end

    # The un-clipped source line to buffer: the whole trip's track, or a
    # single route's own geometry — whichever was passed to .new. Queried by
    # id (not embedded as WKT/WKB) to stay consistent with how boundaries are
    # joined elsewhere (TripTrackSampler#base_geom_sql).
    def scope_geom_sql
      if trip_track
        "SELECT tt.geom FROM trip_tracks tt WHERE tt.trip_id = #{trip_track.trip_id}"
      else
        "SELECT r.geom FROM routes r WHERE r.id = #{route.id}"
      end
    end

    def connection
      ActiveRecord::Base.connection
    end
  end
end
