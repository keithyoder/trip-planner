# frozen_string_literal: true

module NetworkCoverage
  # Mixed into TripTrack to analyze fetched coverage (from any provider)
  # against the trip's stored geom, using the same ST_Intersects /
  # ST_Intersection / ST_Length pattern as Boundary.intersecting_with_route.
  #
  # Every method here accepts an optional `boundary:` (a Boundary record) to
  # scope the analysis to just the portion of the trip within that boundary
  # — e.g. pass the Uruguay Boundary to only look at coverage/gaps for the
  # Uruguay leg, rather than the full multi-country trip track.
  #
  # NOTE: trip_tracks.geom is a MultiLineString with Z (has_z: true), so
  # every query here forces 2D (ST_Force2D) before doing any
  # length/intersection math — PostGIS length/interpolation functions on
  # geography don't want the Z ordinate mixed in, and it's irrelevant for
  # coverage analysis anyway.
  module Analyzable
    extend ActiveSupport::Concern

    included do
      attribute :covered_distance, :distance, units: :meters
      attribute :gap_distance, :distance, units: :meters
    end

    # Total length of the (optionally boundary-clipped) trip track.
    #
    # @param boundary [Boundary, nil]
    # @return [Float] meters
    def track_distance(boundary: nil)
      self.class.connection.select_value(<<~SQL)
        SELECT ST_Length((#{base_geom_sql(boundary: boundary)})::geography)
      SQL
    end

    # Length of the (optionally boundary-clipped) trip track actually
    # covered by the given provider/layer combination.
    #
    # @param provider [String] e.g. "claro"
    # @param layer [String] e.g. "cobertura_externa_4G_UY"
    # @param boundary [Boundary, nil]
    # @return [Float] meters
    def coverage_distance(provider:, layer:, boundary: nil)
      geom_sql = base_geom_sql(boundary: boundary)
      self.class.connection.select_value(<<~SQL)
        SELECT COALESCE(ST_Length(
          (#{NetworkCoverage::Feature.clipped_union_sql(geom_sql, trip_id: trip_id, provider: provider, layer: layer)})::geography
        ), 0)
      SQL
    end

    # Returns the uncovered sub-segments of the (optionally boundary-clipped)
    # trip track, for a given provider/layer, as an RGeo MultiLineString (or
    # nil if the whole clipped track is uncovered / nothing fetched yet).
    #
    # @param provider [String]
    # @param layer [String]
    # @param boundary [Boundary, nil]
    # @return [RGeo::Feature::Geometry, nil]
    def coverage_gaps(provider:, layer:, boundary: nil)
      geom_sql = base_geom_sql(boundary: boundary)
      result = self.class.connection.select_value(<<~SQL)
        SELECT ST_AsGeoJSON(
          ST_Difference(
            (#{geom_sql}),
            COALESCE(
              #{NetworkCoverage::Feature.clipped_union_sql(geom_sql, trip_id: trip_id, provider: provider, layer: layer)},
              ST_GeomFromText('GEOMETRYCOLLECTION EMPTY', 4326)
            )
          )
        )
      SQL
      return nil if result.nil?

      RGeo::GeoJSON.decode(result)
    end

    # Summary combining covered/gap distance and percentage, optionally
    # clipped to a boundary (e.g. pass the Uruguay Boundary to only
    # summarize that country's leg of a multi-country trip).
    #
    # @param provider [String]
    # @param layer [String]
    # @param boundary [Boundary, nil]
    # @return [Hash]
    def coverage_summary(provider:, layer:, boundary: nil)
      total = track_distance(boundary: boundary)
      covered = coverage_distance(provider: provider, layer: layer, boundary: boundary)
      {
        provider: provider,
        layer: layer,
        boundary: boundary&.name,
        total_distance_m: total,
        covered_distance_m: covered,
        gap_distance_m: total - covered,
        covered_pct: total.positive? ? ((covered / total) * 100).round(1) : nil
      }
    end

    private

    def base_geom_sql(boundary: nil)
      if boundary
        <<~SQL
          SELECT ST_Intersection(ST_Force2D(tt.geom::geometry), b.geom::geometry)
          FROM trip_tracks tt, boundaries b
          WHERE tt.trip_id = #{trip_id} AND b.id = #{boundary.id}
        SQL
      else
        <<~SQL
          SELECT ST_Force2D(tt.geom::geometry)
          FROM trip_tracks tt
          WHERE tt.trip_id = #{trip_id}
        SQL
      end
    end

    def quoted(value)
      self.class.connection.quote(value)
    end
  end
end
