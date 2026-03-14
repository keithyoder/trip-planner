# frozen_string_literal: true

module Routing
  # Merges an ordered array of LegResult objects into a single route geometry,
  # segments array, and surfaces hash, then persists the result to the database.
  #
  # Extracted from OrsService so that multiple routing backends (ORS for
  # driving/walking, GoogleMapsService for transit) can each return LegResult
  # objects that are merged and persisted in one place.
  #
  # Responsibilities:
  # - Coordinate deduplication and way_points index offsetting across legs
  # - Surface value offsetting and synthetic promotion (water, hiking)
  # - Surface summary calculation via Haversine distances
  # - Persisting geometry (geom), segments, and surfaces to the routes table
  #
  # @example
  #   legs = ors_service.fetch_legs + google_maps_service.fetch_legs
  #   Routing::MergeService.new(route, legs).call
  #
  class MergeService
    GEO_FACTORY = RGeo::Geographic.spherical_factory(srid: 4326)

    def initialize(route, legs)
      @route = route
      @legs  = legs
    end

    # Merges all legs and persists the result.
    #
    # @return [void]
    def call
      merged = merge_legs
      persist_directions(merged)
    end

    private

    # -- Merge -------------------------------------------------------------

    # Merges LegResult objects into a single coordinates array, segments array,
    # and surfaces hash. Handles:
    # - Coordinate deduplication: the first coordinate of each leg after the
    #   first is dropped because it duplicates the last coordinate of the
    #   previous leg (shared junction point).
    # - way_points index offsetting: each segment's step way_points indices are
    #   shifted by the cumulative coordinate offset so they reference the correct
    #   position in the merged coordinate array.
    # - Surface value offsetting: same offset applied to surface value ranges.
    # - Synthetic hiking surfaces: injected for foot- legs that ORS didn't
    #   return surface data for.
    # - ORS sometimes returns way_points indices that reference coordinates
    #   beyond the end of the geometry (off-by-one in the last step). These are
    #   clamped to max_local_idx before offsetting to prevent out-of-bounds
    #   access in DurationImporter and DirectionsPresenter.
    #
    # @return [Hash] with :coordinates, :segments, :surfaces keys
    def merge_legs
      coordinates     = []
      all_segments    = []
      surfaces_values = []

      @legs.each_with_index do |leg, i|
        leg_coords = i.zero? ? leg.coordinates : leg.coordinates[1..]
        offset     = i.zero? ? 0 : coordinates.size - 1
        coordinates.concat(leg_coords)

        leg.segments.each do |seg|
          max_local_idx  = leg.coordinates.size - 1
          adjusted_steps = seg[:steps].map do |step|
            clamped = step[:way_points].map { |idx| [idx, max_local_idx].min + offset }
            step.merge(way_points: clamped)
          end
          all_segments << seg.merge(steps: adjusted_steps)
        end

        leg.surfaces_values.each do |(start_idx, end_idx, code)|
          surfaces_values << [start_idx + offset, end_idx + offset, code]
        end

        # Inject synthetic hiking surface for foot- legs with no ORS surface data.
        next unless leg.profile.start_with?('foot-') && leg.surfaces_values.empty?

        leg_start   = offset + 1 # skip the shared junction point
        leg_end     = coordinates.size - 1
        hiking_code = Routes::SurfaceProfile::SURFACE_TYPES[:hiking]
        surfaces_values << [leg_start, leg_end, hiking_code]
      end

      promoted_values = promote_surface_values(surfaces_values, coordinates, all_segments)
      summary         = build_surfaces_summary(promoted_values, coordinates)

      {
        coordinates: coordinates,
        segments: all_segments,
        surfaces: { 'summary' => summary, 'values' => promoted_values }
      }
    end

    # -- Persist -----------------------------------------------------------

    def persist_directions(merged)
      @route.update!(
        segments: merged[:segments],
        surfaces: merged[:surfaces]
      )

      geojson = { type: 'LineString', coordinates: merged[:coordinates] }.to_json

      Route.connection.exec_update(
        Route.sanitize_sql(
          [
            'UPDATE routes SET geom = ST_Force4D(ST_GeomFromGeoJSON(:geom)) WHERE id = :id AND trip_id = :trip_id',
            { id: @route.id, trip_id: @route.trip_id, geom: geojson }
          ]
        )
      )
    end

    # -- Surface promotion -------------------------------------------------

    # Promotes surface codes to :water or :hiking based on geometry index ranges.
    #
    # @param values       [Array] [[start_idx, end_idx, code], ...]
    # @param coordinates  [Array] [[lon, lat, ele], ...]
    # @param all_segments [Array] merged segments with adjusted way_points
    # @return [Array]
    def promote_surface_values(values, coordinates, all_segments)
      unknown_code = Routes::SurfaceProfile::SURFACE_TYPES[:unknown]
      water_code   = Routes::SurfaceProfile::SURFACE_TYPES[:water]
      hiking_code  = Routes::SurfaceProfile::SURFACE_TYPES[:hiking]

      ferry_ranges  = ferry_index_ranges(coordinates)
      hiking_ranges = hiking_index_ranges(all_segments)

      return values if ferry_ranges.empty? && hiking_ranges.empty?

      values.map do |(start_idx, end_idx, code)|
        # Use exclusive end ranges for overlap to avoid false positives at
        # shared junction points between legs.
        segment_range  = start_idx...end_idx
        effective_code = if ferry_ranges.any? do |r|
          (r.first...r.last).overlaps?(segment_range)
        end && code == unknown_code
                           water_code
                         elsif hiking_ranges.any? { |r| (r.first...r.last).overlaps?(segment_range) }
                           hiking_code
                         else
                           code
                         end
        [start_idx, end_idx, effective_code]
      end
    end

    # Builds surface summary by summing geodesic distances per surface code.
    #
    # @param promoted_values [Array] [[start_idx, end_idx, code], ...]
    # @param coordinates     [Array] [[lon, lat, ele], ...]
    # @return [Array<Hash>]
    def build_surfaces_summary(promoted_values, coordinates)
      totals = Hash.new(0.0)

      promoted_values.each do |(start_idx, end_idx, code)|
        distance = (start_idx...end_idx).sum do |i|
          GEO_FACTORY.point(coordinates[i][0], coordinates[i][1])
                     .distance(GEO_FACTORY.point(coordinates[i + 1][0], coordinates[i + 1][1]))
        end
        totals[code] += distance
      end

      total = totals.values.sum
      totals
        .map do |value, distance|
          {
            'value' => value,
            'distance' => distance.round(1),
            'amount' => total.positive? ? (distance / total * 100).round(2) : 0.0
          }
        end
        .sort_by { |s| -s['amount'] }
    end

    # Snaps ferry_boarding/disembarkment waypoint pairs to geometry indices.
    #
    # @param coordinates [Array] [[lon, lat, ...], ...]
    # @return [Array<Range>]
    def ferry_index_ranges(coordinates)
      boardings      = waypoints.select(&:ferry_boarding?)
      disembarkments = waypoints.select(&:ferry_disembarkment?)

      boardings.filter_map do |boarding|
        disembark = disembarkments.find { |d| d.sequence > boarding.sequence }
        next unless disembark

        start_idx = closest_coordinate_index(coordinates, boarding.lonlat.x, boarding.lonlat.y)
        end_idx   = closest_coordinate_index(coordinates, disembark.lonlat.x, disembark.lonlat.y)
        start_idx..end_idx
      end
    end

    # Returns geometry index ranges for foot- profile legs.
    # Segments map 1:1 to all non-routing arriving waypoints (including transit).
    #
    # @param all_segments [Array] merged segments with adjusted way_points
    # @return [Array<Range>]
    def hiking_index_ranges(all_segments)
      # Build leg profiles from consecutive non-routing pairs, matching the
      # order legs were fetched. Each pair (a, b) produces one segment whose
      # profile is b.profile (the arriving waypoint's profile).
      leg_profiles = waypoints
                     .reject(&:routing?)
                     .each_cons(2)
                     .map { |_a, b| b.profile }

      all_segments.zip(leg_profiles).filter_map do |segment, profile|
        next unless profile&.start_with?('foot-')

        steps     = segment[:steps] || segment['steps'] || []
        start_idx = steps.first&.dig(:way_points, 0) || steps.first&.dig('way_points', 0)
        end_idx   = steps.last&.dig(:way_points, -1) || steps.last&.dig('way_points', -1)
        next unless start_idx && end_idx

        (start_idx + 1)..end_idx
      end
    end

    def closest_coordinate_index(coordinates, lon, lat)
      coordinates
        .each_with_index
        .min_by { |c, _| (c[0] - lon)**2 + (c[1] - lat)**2 }
        .last
    end

    def waypoints
      @waypoints ||= @route.waypoints.to_a
    end
  end
end
