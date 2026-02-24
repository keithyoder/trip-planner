# frozen_string_literal: true

module Routes
  module ElevationProfile
    extend ActiveSupport::Concern

    # RGeo factory with Z coordinate support for elevation data
    GEO_FACTORY = RGeo::Geographic.spherical_factory(srid: 4326, has_z_coordinate: true)

    # Bucket size in meters — one point retained per 100m of route distance
    BUCKET_SIZE_METERS = 100

    # Value object representing a single point on the elevation profile.
    # distance is a Units::Distance in the locale's preferred unit.
    # elevation is a raw Float in the locale's preferred unit.
    ElevationPoint = Data.define(:index, :latitude, :longitude, :elevation, :distance)

    included do
      # Returns a bucketed elevation profile for this route, with distance and
      # elevation values converted to the current locale's preferred units.
      #
      # @return [Array<ElevationPoint>]
      def elevations
        return [] unless geom

        distance_unit = I18n.t('units.distance').to_sym
        elevation_unit = I18n.t('units.elevation').to_sym

        extract_points(distance_unit, elevation_unit).then { |points| bucket_points(points) }
      end
    end

    private

    # Walks each point in the route geometry, accumulating distance and
    # converting units as it goes.
    #
    # @param distance_unit [Symbol] e.g. :km, :miles
    # @param elevation_unit [Symbol] e.g. :meters, :feet
    # @return [Array<ElevationPoint>]
    def extract_points(distance_unit, elevation_unit)
      cumulative = 0.0
      previous = nil

      geom.points.each_with_index.map do |point, index|
        cumulative += previous ? previous.distance(point) : 0.0
        previous = point

        ElevationPoint.new(
          index: index + 1,
          latitude: point.y,
          longitude: point.x,
          elevation: Units::Distance.new(point.z || 0.0).to_units(elevation_unit).value.to_f,
          distance: Units::Distance.new(cumulative).to_units(distance_unit)
        )
      end
    end

    # Retains the first point in each 100m bucket, reducing the number of
    # points to a manageable set for charting. Bucketing is always done in
    # meters regardless of display unit to ensure consistent resolution.
    #
    # @param points [Array<ElevationPoint>]
    # @return [Array<ElevationPoint>]
    def bucket_points(points)
      points
        .group_by { |p| (p.distance.meters.value / BUCKET_SIZE_METERS).floor }
        .map { |_, bucket| bucket.first }
    end
  end
end
