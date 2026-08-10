# frozen_string_literal: true

require 'json'

module NetworkCoverage
  # Samples points every N meters along a TripTrack's stored geom, using
  # PostGIS itself to do the distance-along-line math (not Ruby).
  #
  # Extracted so every provider-specific fetcher (Claro AR/UY via WMS, Claro
  # Chile via ArcGIS FeatureServer, future providers) shares identical
  # sampling behavior rather than each reimplementing the same SQL.
  #
  # trip_tracks.geom is a MultiLineString with Z. Each component line
  # (post-clip, if a boundary is given) is dumped and interpolated
  # separately so spacing stays consistent even where the track is made of
  # several disjoint pieces (e.g. ferry gaps, disjoint driving legs).
  #
  # Usage:
  #   Coverage::TripTrackSampler.points_for(trip_track: trip.trip_track, boundary: uruguay, spacing_meters: 1000)
  #   # => [[lon, lat], [lon, lat], ...]
  #
  class TripTrackSampler
    def self.points_for(trip_track:, boundary: nil, spacing_meters: 1000)
      new(trip_track: trip_track, boundary: boundary, spacing_meters: spacing_meters).points
    end

    def initialize(trip_track:, boundary:, spacing_meters:)
      @trip_track = trip_track
      @boundary = boundary
      @spacing_meters = spacing_meters
    end

    def points
      @points ||= ActiveRecord::Base.connection.select_all(sql).map do |row|
        JSON.parse(row['pt'])['coordinates']
      end
    end

    private

    attr_reader :trip_track, :boundary, :spacing_meters

    def sql
      <<~SQL
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
  end
end
