# frozen_string_literal: true

# == Schema Information
#
# Table name: routes
#
#  id                :bigint           not null, primary key
#  waypoint_start_id :bigint           not null
#  waypoint_end_id   :bigint           not null
#  segments          :jsonb
#  geom              :geography        linestring, 4326
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  start_time        :interval
#  trip_id           :bigint
#  profile           :string           default("driving-car"), not null
#  surfaces          :jsonb
#  status            :integer          default(0), not null
#
class Route < ApplicationRecord
  include Statusable
  include Routes::ElevationProfile
  include Routes::ElevationAnalysis
  include Routes::SurfaceProfile

  belongs_to :trip
  has_one :route_sequence
  belongs_to :waypoint_start, class_name: 'Waypoint'
  belongs_to :waypoint_end, class_name: 'Waypoint'

  after_create_commit { enqueue_calculate_route }
  after_update_commit { enqueue_calculate_route if waypoints_changed? }

  validate :only_one_in_progress_route_per_trip, if: :in_progress?
  validate :only_first_non_terminal_route_editable, if: :status_changed?

  scope :bounding_box, lambda {
    select('ST_Envelope(geom::geometry) AS bounding_box, *')
  }

  scope :distance_to_point, lambda { |lat, lng|
    select(["ST_Distance(geom, ST_Point(#{lng}, #{lat})) as distance"])
  }

  scope :with_bbox, lambda { |padding_meters = 5000|
    select(
      '*',
      "ST_XMin(ST_Envelope(ST_Buffer(geom::geography, #{padding_meters})::geometry)) AS bbox_w",
      "ST_XMax(ST_Envelope(ST_Buffer(geom::geography, #{padding_meters})::geometry)) AS bbox_e",
      "ST_YMin(ST_Envelope(ST_Buffer(geom::geography, #{padding_meters})::geometry)) AS bbox_s",
      "ST_YMax(ST_Envelope(ST_Buffer(geom::geography, #{padding_meters})::geometry)) AS bbox_n"
    )
  }

  scope :without_geom, -> { select(column_names - ['geom']) }

  def waypoints
    @waypoints ||= trip.waypoints
                       .where(sequence: waypoint_start.sequence..waypoint_end.sequence)
                       .order(:sequence)
  end

  # Returns [[lon, lat], ...] for all waypoints on this route.
  # Used internally by Routes::OrsService; available to callers that need
  # raw coordinate arrays (e.g. GeoJSON serialization).
  # For a Google Maps URL use RoutePresenter#google_maps_url instead.
  def waypoints_coordinates
    waypoints.map { |wp| [wp.lonlat.x, wp.lonlat.y] }
  end

  # Delegates to Routes::GeometryService — see app/services/routes/geometry_service.rb
  def points
    Routing::GeometryService.new(self).points
  end

  # Delegates to Routes::GeometryService — see app/services/routes/geometry_service.rb
  def boundaries
    Routing::GeometryService.new(self).boundaries
  end

  # Delegates to Routes::GeometryService — see app/services/routes/geometry_service.rb
  def closest_point_info(lat, lon)
    Routing::GeometryService.new(self).closest_point_info(lat, lon)
  end

  def self.find_by_waypoint(waypoint)
    where(trip_id: waypoint.trip_id)
      .joins(%i[waypoint_start waypoint_end])
      .where("#{waypoint.sequence} BETWEEN waypoints.sequence AND waypoint_ends_routes.sequence")
      .first
  end

  # Filters out surface types below a minimum distance threshold.
  # Threshold is always in meters for consistency regardless of display unit.
  #
  # @param min_meters [Float] minimum distance in meters to include (default: 1000m)
  # @return [Array<SurfaceSummary>]
  def significant_surfaces(min_meters: 1000)
    surface_summary.select { |s| s.distance.meters.value >= min_meters }
  end

  # Sums ORS segment durations for legs whose arriving waypoint matches
  # the given condition. Segments map 1:1 with waypoint-to-waypoint legs
  # in order, with each segment's duration representing travel time for
  # that leg excluding stop delays.
  #
  # Accepts an optional +preloaded_waypoints+ array to avoid DB queries when
  # all trip waypoints have been loaded in memory (e.g. from the controller).
  #
  # @param preloaded_waypoints [Array<Waypoint>, nil]
  # @yield [Waypoint] the arriving waypoint for each leg
  # @return [Float] total seconds
  def leg_duration_for(preloaded_waypoints: nil, &condition)
    return 0.0 unless segments.present?

    arriving_wps = arriving_waypoints_for(preloaded_waypoints)

    segments.each_with_index.sum do |segment, i|
      arriving_waypoint = arriving_wps[i]
      next 0.0 unless arriving_waypoint && !arriving_waypoint.routing?
      next 0.0 unless condition.call(arriving_waypoint)

      segment['duration'].to_f
    end
  end

  # Sums segment distances for legs whose arriving waypoint is a driving leg
  # (excludes ferry crossings, foot-hiking legs, and transit legs).
  #
  # Accepts an optional +preloaded_waypoints+ array to avoid DB queries when
  # all trip waypoints have been loaded in memory (e.g. from the controller).
  #
  # @param preloaded_waypoints [Array<Waypoint>, nil]
  # @return [Float] driving distance in metres
  def driving_distance_meters(preloaded_waypoints: nil)
    return 0.0 unless segments.present?

    arriving_waypoints_for(preloaded_waypoints).each_with_index.sum do |arriving_waypoint, i|
      next 0.0 unless arriving_waypoint && !arriving_waypoint.routing?
      next 0.0 if arriving_waypoint.ferry_disembarkment?
      next 0.0 if arriving_waypoint.profile.start_with?('foot-')
      next 0.0 if arriving_waypoint.transit?

      segments[i]['distance'].to_f
    end
  end

  # A route can only have its status changed once every earlier route in
  # the trip's sequence has reached a terminal state (completed or
  # skipped) -- you work through the trip in order, you don't jump ahead.
  def actionable?
    return true unless route_sequence

    !trip.routes
         .joins(:route_sequence)
         .where.not(id: id)
         .where('route_sequences.sequence < ?', route_sequence.sequence)
         .where.not(status: %i[completed skipped])
         .exists?
  end

  private

  # Returns the arriving waypoints (all except the departure) for segment
  # iteration. Uses the preloaded array when available to avoid a DB query.
  #
  # @param preloaded_waypoints [Array<Waypoint>, nil]
  # @return [Array<Waypoint>]
  def arriving_waypoints_for(preloaded_waypoints)
    return waypoints.to_a[1..] unless preloaded_waypoints

    start_seq = waypoint_start.sequence
    end_seq   = waypoint_end.sequence
    preloaded_waypoints
      .select { |wp| wp.sequence > start_seq && wp.sequence <= end_seq }
      .sort_by(&:sequence)
  end

  def enqueue_calculate_route
    CalculateRouteJob.perform_later(id)
  end

  def waypoints_changed?
    saved_change_to_waypoint_start_id? || saved_change_to_waypoint_end_id?
  end

  def only_one_in_progress_route_per_trip
    return unless trip.routes.where(status: :in_progress).where.not(id: id).exists?

    errors.add(:status, 'another route on this trip is already in progress')
  end

  def only_first_non_terminal_route_editable
    return if actionable?

    errors.add(:status, 'can only change status once all earlier routes are completed or skipped')
  end
end
