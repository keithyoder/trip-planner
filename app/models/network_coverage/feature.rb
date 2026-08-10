# frozen_string_literal: true

module NetworkCoverage
  # == Schema Information
  #
  # Table name: coverage_features
  #
  #  id                 :bigint           not null, primary key
  #  trip_id            :bigint           not null
  #  provider           :string           not null
  #  layer              :string           not null
  #  source_feature_id  :string
  #  geom               :geometry         multipolygon, 4326
  #  fetched_at         :datetime         not null
  #  created_at         :datetime         not null
  #  updated_at         :datetime         not null
  #
  # Generic store for any fetched coverage geometry (cell carrier maps,
  # satellite service maps, etc.) tied to a trip. `provider` distinguishes
  # the source (e.g. "claro", "starlink"); `layer` distinguishes a specific
  # sub-layer within that provider (e.g. a technology or country variant).
  #
  class Feature < ApplicationRecord
    self.table_name = 'coverage_features'

    belongs_to :trip

    scope :for_trip, ->(trip_id) { where(trip_id: trip_id) }
    scope :for_provider, ->(provider) { where(provider: provider) }
    scope :for_layer, ->(layer) { where(layer: layer) }

    # Bounding-box-accelerated filter: only rows whose geom's bbox overlaps
    # the given geometry SQL expression (a scalar subquery returning one
    # geometry). Uses the && operator so the GiST index on geom can
    # eliminate non-overlapping rows without ever touching the actual
    # polygon shape — this is what makes clipped_union_sql cheap even when
    # the table holds large, complex polygons far from the area of interest.
    #
    # @param geom_sql [String] SQL expression (without parens) evaluating to a single geometry
    scope :overlapping, ->(geom_sql) { where("coverage_features.geom && (#{geom_sql})") }

    # Builds a SQL expression that clips each matching row to `geom_sql`
    # FIRST (a cheap per-row ST_Intersection), then unions only those
    # already-small clipped pieces — rather than unioning every raw fetched
    # polygon and intersecting once at the end. Fetched polygons can be
    # enormous (a single feature sometimes covers an entire country), so
    # unioning them before clipping wastes most of the work on geometry
    # that's nowhere near the area actually being analyzed.
    #
    # Shared by NetworkCoverage::Analyzable (intersecting against the raw
    # route line for coverage/gap distance) and NetworkCoverage::Union
    # (intersecting against a buffered corridor for simplified export).
    #
    # @param geom_sql [String] SQL expression (without parens) evaluating to a single geometry
    # @param trip_id [Integer]
    # @param provider [String]
    # @param layer [String]
    # @return [String] SQL expression evaluating to a single (possibly
    #   multi-part) geometry, or NULL if nothing matched
    def self.clipped_union_sql(geom_sql, trip_id:, provider:, layer:)
      rows_sql = for_trip(trip_id).for_provider(provider).for_layer(layer)
                                  .overlapping(geom_sql)
                                  .select('coverage_features.geom')
                                  .to_sql

      <<~SQL
        (SELECT ST_Union(clipped.g) FROM (
           SELECT ST_Intersection(rows.geom::geometry, (#{geom_sql})) AS g
           FROM (#{rows_sql}) AS rows
         ) AS clipped
         WHERE NOT ST_IsEmpty(clipped.g))
      SQL
    end

    # Check whether a point already falls within any previously-fetched
    # coverage polygon for this trip/provider/layer. Used by fetchers to
    # skip an external request entirely when the point is already known to
    # be covered — a single large returned polygon frequently covers many
    # subsequent sample points along a route, so this can eliminate a large
    # fraction of requests in areas with broad, contiguous coverage.
    #
    # @param trip [Trip]
    # @param provider [String]
    # @param layer [String]
    # @param lon [Float]
    # @param lat [Float]
    # @return [Boolean]
    def self.covers_point?(trip:, provider:, layer:, lon:, lat:)
      connection.select_value(<<~SQL)
        SELECT EXISTS (
          SELECT 1 FROM coverage_features
          WHERE trip_id = #{trip.id}
            AND provider = #{connection.quote(provider)}
            AND layer = #{connection.quote(layer)}
            AND ST_Intersects(geom::geometry, ST_SetSRID(ST_MakePoint(#{lon}, #{lat}), 4326))
        )
      SQL
    end

    # Upsert a feature fetched from a provider's API response, keyed by
    # (trip, provider, layer, source_feature_id) so re-running a fetcher
    # doesn't duplicate rows.
    #
    # Uses raw SQL with ST_GeomFromGeoJSON rather than RGeo::GeoJSON.decode +
    # ActiveRecord save!. Some coverage features come back as very large,
    # high-vertex-count polygons — decoding those in pure Ruby (RGeo) can
    # take an extremely long time; letting PostGIS parse the GeoJSON in C is
    # dramatically faster and avoids that hang entirely. This also collapses
    # the operation into a single INSERT ... ON CONFLICT round-trip instead
    # of a SELECT followed by a separate INSERT/UPDATE.
    #
    # @param trip [Trip]
    # @param provider [String]
    # @param layer [String]
    # @param source_feature_id [String]
    # @param geojson_geometry [Hash] the "geometry" key from a GeoJSON feature
    def self.upsert_from_geojson!(trip:, provider:, layer:, source_feature_id:, geojson_geometry:)
      conn = connection
      conn.execute(<<~SQL)
        INSERT INTO coverage_features (trip_id, provider, layer, source_feature_id, geom, fetched_at, created_at, updated_at)
        VALUES (
          #{conn.quote(trip.id)},
          #{conn.quote(provider)},
          #{conn.quote(layer)},
          #{conn.quote(source_feature_id)},
          ST_Multi(ST_Force2D(ST_SetSRID(ST_GeomFromGeoJSON(#{conn.quote(geojson_geometry.to_json)}), 4326))),
          now(), now(), now()
        )
        ON CONFLICT (trip_id, provider, layer, source_feature_id)
        DO UPDATE SET geom = EXCLUDED.geom, fetched_at = EXCLUDED.fetched_at, updated_at = now()
      SQL
    end
  end
end
