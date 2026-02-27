# frozen_string_literal: true

module Routes
  module SurfaceProfile
    extend ActiveSupport::Concern

    SURFACE_TYPES = {
      unknown: 0,
      paved: 1,
      unpaved: 2,
      asphalt: 3,
      concrete: 4,
      cobblestone: 5,
      metal: 6,
      wood: 7,
      compacted_gravel: 8,
      fine_gravel: 9,
      gravel: 10,
      dirt: 11,
      ground: 12,
      ice: 13,
      paving_stones: 14,
      sand: 15,
      woodchips: 16,
      grass: 17,
      grass_paver: 18
    }.freeze

    # Groups surfaces into broader categories for simplified display.
    # Useful for colour-coding the map without needing 19 different colours.
    SURFACE_CATEGORIES = {
      unknown: :unknown,
      paved: :paved,
      unpaved: :unpaved,
      asphalt: :paved,
      concrete: :paved,
      cobblestone: :paved,
      metal: :paved,
      wood: :unpaved,
      compacted_gravel: :unpaved,
      fine_gravel: :unpaved,
      gravel: :unpaved,
      dirt: :unpaved,
      ground: :unpaved,
      ice: :unpaved,
      paving_stones: :paved,
      sand: :unpaved,
      woodchips: :unpaved,
      grass: :unpaved,
      grass_paver: :unpaved
    }.freeze

    # Value object for a single surface segment with its geometry.
    # points is an array of [lat, lon] pairs following the road.
    SurfaceSegment = Data.define(
      :surface_type,    # Symbol  — e.g. :asphalt, :gravel
      :category,        # Symbol  — :paved | :unpaved | :unknown
      :start_index,     # Integer — index into route geometry
      :end_index,       # Integer — index into route geometry
      :points           # Array<Array<Float>> — [[lat, lon], ...] for map rendering
    )

    # Value object for the overall surface summary.
    SurfaceSummary = Data.define(
      :surface_type,    # Symbol
      :category,        # Symbol
      :distance,        # Units::Distance
      :percent          # Float
    )

    included do
      # Returns each contiguous surface segment with its geometry points.
      # Useful for rendering surface-coded polylines on a map.
      #
      # @return [Array<SurfaceSegment>]
      def surface_segments
        return [] unless surfaces && geom

        geometry_points = geom.points

        surfaces['values'].map do |start_idx, end_idx, surface_code|
          type     = SURFACE_TYPES.key(surface_code) || :other
          category = SURFACE_CATEGORIES.fetch(type, :unknown)

          SurfaceSegment.new(
            surface_type: type,
            category: category,
            start_index: start_idx,
            end_index: end_idx,
            points: geometry_points[start_idx..end_idx].map { |p| [p.y, p.x] }
          )
        end
      end

      # Returns the overall surface breakdown from the ORS summary.
      # Useful for displaying a legend or surface breakdown chart.
      #
      # @return [Array<SurfaceSummary>]
      def surface_summary
        return [] unless surfaces
        return [] unless surfaces['summary']

        distance_unit = I18n.t('units.distance').to_sym

        surfaces['summary']
          .map do |s|
            type     = SURFACE_TYPES.key(s['value'].to_i) || :other
            category = SURFACE_CATEGORIES.fetch(type, :unknown)

            SurfaceSummary.new(
              surface_type: type,
              category: category,
              distance: Units::Distance.new(s['distance']).to_units(distance_unit),
              percent: s['amount'].to_f
            )
          end
          .sort_by { |s| -s.percent }
      end

      # Convenience grouping of segments by category for map rendering.
      # Returns a hash of :paved, :unpaved, :unknown each with their segments.
      #
      # @return [Hash<Symbol, Array<SurfaceSegment>>]
      def surface_segments_by_category
        surface_segments.group_by(&:category)
      end
    end
  end
end
