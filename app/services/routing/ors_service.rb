# frozen_string_literal: true

module Routing
  # Handles all OpenRouteService API interactions for a route.
  #
  # Responsibilities:
  # - Fetching directions (geometry, segments, surfaces) from ORS
  # - Fetching elevation data and stitching it back into the route geometry
  # - Persisting results directly to the routes table via raw SQL
  #
  # Supports multi-profile routes by splitting waypoints into contiguous legs
  # sharing the same profile, making one ORS call per leg, then merging the
  # results into a single geometry, segments array, and surfaces hash.
  #
  # Surface summary is calculated from the promoted values array using Haversine
  # distances rather than stored from ORS, ensuring consistency with synthetic
  # surface promotions (water for ferry crossings, hiking for foot- profile legs).
  #
  # @example
  #   Routing::OrsService.new(route).calculate
  #   Routing::OrsService.new(route).import_elevation
  #
  class OrsService
    ELEVATION_POINT_LIMIT = 1999

    # Carries raw ORS response data for a single profile leg before merging.
    # surfaces_summary is intentionally excluded — we calculate it ourselves
    # from the promoted values array for accuracy and consistency.
    LegResult = Data.define(
      :profile,
      :coordinates,
      :segments,
      :surfaces_values
    )

    def initialize(route)
      @route = route
    end

    # Fetches directions from ORS and persists geometry, segments, and surfaces.
    # Makes one ORS call per distinct waypoint profile, then merges results.
    #
    # @return [void]
    def calculate
      legs   = fetch_all_legs
      merged = merge_legs(legs)
      persist_directions(merged)
    end

    # Fetches elevation data from ORS and writes it into the route geometry as
    # a 4D (XYZM) LineString. Splits the geometry into two halves first when the
    # route exceeds the ORS point limit.
    #
    # @return [void]
    def import_elevation
      sql = if @route.geom.num_points > ELEVATION_POINT_LIMIT
              elevation_sql_for_split_route
            else
              elevation_sql_for_full_route
            end

      Route.connection.exec_update(sql)
    end

    private

    # -- Directions --------------------------------------------------------

    # Splits waypoints into contiguous legs by profile and fetches one ORS
    # response per leg.
    #
    # @return [Array<LegResult>]
    def fetch_all_legs
      waypoint_legs.map do |leg|
        Rails.logger.debug "[OrsService] Fetching #{leg[:profile]} leg with #{leg[:coordinates].size} waypoints"

        response = client.post(
          "/v2/directions/#{leg[:profile]}/geojson",
          {
            elevation: true,
            extra_info: %w[tollways surface waycategory waytype],
            coordinates: leg[:coordinates]
          }
        )

        feature = response[:features].first
        extras  = feature[:properties][:extras] || {}
        surface = extras[:surface] || {}

        LegResult.new(
          profile: leg[:profile],
          coordinates: feature[:geometry][:coordinates],
          segments: feature[:properties][:segments],
          surfaces_values: surface[:values] || []
        )
      end
    end

    # Groups consecutive waypoint pairs by the arriving waypoint's profile.
    # The first waypoint is always the departure point — its profile belongs
    # to the previous route's final leg and is intentionally ignored here.
    #
    # @return [Array<Hash>] each with :profile and :coordinates
    def waypoint_legs
      waypoints
        .each_cons(2)
        .chunk { |_a, b| b.profile }
        .map do |profile, pairs|
          leg_waypoints = [pairs.first.first, *pairs.map(&:last)]
          {
            profile: profile,
            coordinates: leg_waypoints.map { |wp| [wp.lonlat.x, wp.lonlat.y] }
          }
        end
    end

    # Merges an array of LegResults into a single hash ready for persist_directions.
    #
    # Handles coordinate deduplication, way_points index offsetting, and surface
    # values index offsetting. Synthetic surface promotion (water, hiking) is
    # applied after merging using the fully-offset all_segments array so that
    # hiking ranges are derived from way_points indices rather than coordinate
    # snapping. Surface summary is calculated from promoted values via Haversine.
    #
    # @param legs [Array<LegResult>]
    # @return [Hash] with :coordinates, :segments, and :surfaces keys
    def merge_legs(legs)
      coordinates     = []
      all_segments    = []
      surfaces_values = []

      legs.each_with_index do |leg, i|
        leg_coords = i.zero? ? leg.coordinates : leg.coordinates[1..]
        offset = i.zero? ? 0 : coordinates.size - 1
        coordinates.concat(leg_coords)

        leg.segments.each do |seg|
          adjusted_steps = seg[:steps].map do |step|
            step.merge(way_points: step[:way_points].map { |idx| idx + offset })
          end
          all_segments << seg.merge(steps: adjusted_steps)
        end

        leg.surfaces_values.each do |(start_idx, end_idx, code)|
          surfaces_values << [start_idx + offset, end_idx + offset, code]
        end

        next unless leg.profile.start_with?('foot-') && leg.surfaces_values.empty?

        leg_start   = offset + 1 # skip the shared junction point
        leg_end     = coordinates.size - 1
        hiking_code = Routes::SurfaceProfile::SURFACE_TYPES[:hiking]
        surfaces_values << [leg_start, leg_end, hiking_code]
      end

      # Promote synthetic surface codes using the fully-offset segments array.
      # Hiking ranges are derived from way_points indices — no coordinate
      # snapping required, avoiding duplicate-location ambiguity.
      promoted_values = promote_surface_values(surfaces_values, coordinates, all_segments)

      Rails.logger.debug "[OrsService] promoted_values: #{promoted_values.inspect}"

      # Calculate summary from promoted values using Haversine distances.
      # This replaces the ORS-provided summary entirely for consistency.
      summary = build_surfaces_summary(promoted_values, coordinates)

      {
        coordinates: coordinates,
        segments: all_segments,
        surfaces: { 'summary' => summary, 'values' => promoted_values }
      }
    end

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

    # Promotes surface codes to :water or :hiking based on geometry index
    # ranges. Ferry ranges are derived from waypoint coordinate snapping;
    # hiking ranges are derived from the already-offset segment way_points
    # indices, which are unambiguous regardless of duplicate coordinates.
    #
    # @param values       [Array] [[start_idx, end_idx, code], ...]
    # @param coordinates  [Array] [[lon, lat, ele], ...]
    # @param all_segments [Array] merged segments with adjusted way_points
    # @return [Array] promoted values
    def promote_surface_values(values, coordinates, all_segments)
      unknown_code = Routes::SurfaceProfile::SURFACE_TYPES[:unknown]
      water_code   = Routes::SurfaceProfile::SURFACE_TYPES[:water]
      hiking_code  = Routes::SurfaceProfile::SURFACE_TYPES[:hiking]

      ferry_ranges  = ferry_index_ranges(coordinates)
      hiking_ranges = hiking_index_ranges(all_segments)

      return values if ferry_ranges.empty? && hiking_ranges.empty?

      values.map do |(start_idx, end_idx, code)|
        segment_range  = start_idx..end_idx
        effective_code = if ferry_ranges.any? { |r| r.overlaps?(segment_range) } && code == unknown_code
                           water_code
                         elsif hiking_ranges.any? { |r| r.overlaps?(segment_range) }
                           hiking_code
                         else
                           code
                         end
        [start_idx, end_idx, effective_code]
      end
    end

    # Builds the surface summary by summing Haversine distances per surface
    # code across all promoted value triples.
    #
    # Replaces the ORS-provided summary entirely, ensuring the summary is
    # always consistent with the promoted values array.
    #
    # @param promoted_values [Array] [[start_idx, end_idx, code], ...]
    # @param coordinates     [Array] [[lon, lat, ele], ...]
    # @return [Array<Hash>] sorted by descending distance percentage
    def build_surfaces_summary(promoted_values, coordinates)
      totals = Hash.new(0.0)

      promoted_values.each do |(start_idx, end_idx, code)|
        distance = (start_idx...end_idx).sum do |i|
          haversine_distance(
            coordinates[i][1],     coordinates[i][0],
            coordinates[i + 1][1], coordinates[i + 1][0]
          )
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

    # Snaps ferry_boarding and ferry_disembarkment waypoint pairs to geometry
    # indices and returns the index ranges between them.
    # Coordinate snapping is acceptable here because ferry boarding/disembarkment
    # waypoints are at distinct locations with no ambiguity.
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

    # Returns geometry index ranges for foot- profile legs using the
    # already-offset way_points indices from the merged segments array.
    # Each merged segment aligns 1:1 with an arriving waypoint (waypoints[1..]).
    # No coordinate snapping — avoids duplicate-location ambiguity entirely.
    #
    # @param all_segments [Array] merged segments with adjusted way_points
    # @return [Array<Range>]
    def hiking_index_ranges(all_segments)
      arriving_waypoints = waypoints.drop(1)

      all_segments.zip(arriving_waypoints).filter_map do |segment, arriving_wp|
        next unless arriving_wp&.profile&.start_with?('foot-')

        steps     = segment[:steps] || segment['steps'] || []
        start_idx = steps.first&.dig(:way_points, 0) || steps.first&.dig('way_points', 0)
        end_idx   = steps.last&.dig(:way_points, -1) || steps.last&.dig('way_points', -1)
        next unless start_idx && end_idx

        (start_idx + 1)..end_idx # +1 to skip the shared junction point
      end
    end

    # Finds the index of the closest coordinate to the given lon/lat using
    # squared Euclidean distance — sufficient for proximity snapping.
    #
    # @param coordinates [Array] [[lon, lat, ...], ...]
    # @param lon [Float]
    # @param lat [Float]
    # @return [Integer]
    def closest_coordinate_index(coordinates, lon, lat)
      coordinates
        .each_with_index
        .min_by { |c, _| (c[0] - lon)**2 + (c[1] - lat)**2 }
        .last
    end

    # Calculates the Haversine distance in metres between two lat/lon points.
    #
    # @param lat1 [Float]
    # @param lon1 [Float]
    # @param lat2 [Float]
    # @param lon2 [Float]
    # @return [Float] distance in metres
    def haversine_distance(lat1, lon1, lat2, lon2)
      r    = 6_371_000.0
      dlat = (lat2 - lat1) * Math::PI / 180
      dlon = (lon2 - lon1) * Math::PI / 180
      a    = Math.sin(dlat / 2)**2 +
             Math.cos(lat1 * Math::PI / 180) *
             Math.cos(lat2 * Math::PI / 180) *
             Math.sin(dlon / 2)**2
      r * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
    end

    # -- Elevation ---------------------------------------------------------

    def elevation_sql_for_full_route
      Route.sanitize_sql(
        [
          'UPDATE routes SET geom = ST_Force4D(ST_GeomFromGeoJSON(:geom)) WHERE id = :id',
          { id: @route.id, geom: fetch_elevation_geojson(@route.geom) }
        ]
      )
    end

    def elevation_sql_for_split_route
      Route.sanitize_sql(
        [
          <<~SQL,
            UPDATE routes
            SET geom = ST_Force4D(ST_MakeLine(
              ST_GeomFromGeoJSON(:geom1),
              ST_GeomFromGeoJSON(:geom2)
            ))
            WHERE id = :id
          SQL
          {
            id: @route.id,
            geom1: fetch_elevation_geojson(subsegment(1)),
            geom2: fetch_elevation_geojson(subsegment(2))
          }
        ]
      )
    end

    def fetch_elevation_geojson(line)
      geojson = RGeo::GeoJSON.encode(line)
      geojson['coordinates'].each { |c| c.delete_at(2) }
      response = client.post('/elevation/line', { format_in: 'geojson', geometry: geojson })
      Rails.logger.debug "[OrsService] Elevation points: #{response[:geometry][:coordinates].count}"
      response[:geometry].to_json
    end

    def subsegment(segment)
      sql = Arel.sql(
        Route.sanitize_sql(
          [
            <<~SQL, segment
              ST_GeometryN(
                ST_Split(
                  geom::geometry,
                  ST_GeometryN(ST_Points(geom::geometry), ST_NPoints(geom::geometry)/2)
                ), ?
              )::geography AS geom
            SQL
          ]
        )
      )
      @route.trip.routes.where(id: @route.id).pluck(sql).first
    end

    # -- Helpers -----------------------------------------------------------

    def waypoints
      @waypoints ||= @route.waypoints.to_a
    end

    def client
      @client ||= OpenRouteService.new
    end
  end
end
