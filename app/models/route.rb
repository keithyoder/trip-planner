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
#
class Route < ApplicationRecord
  belongs_to :trip
  has_one :route_sequence
  has_many :elevations, class_name: 'RouteElevation'
  belongs_to :waypoint_start, class_name: 'Waypoint'
  belongs_to :waypoint_end, class_name: 'Waypoint'

  after_create_commit { enqueue_calculate_route }
  after_update_commit { enqueue_calculate_route if waypoints_changed? }

  scope :bounding_box, lambda {
    select('ST_Envelope(geom::geometry) AS bounding_box, *')
  }

  scope :distance_to_point, lambda { |lat, lng|
    select(["ST_Distance(geom, ST_Point(#{lng}, #{lat})) as distance"])
  }

  scope :with_bbox, lambda { |padding_meters = 5000|
    select(
      '*',
      "ST_XMin(ST_Expand(geom::geometry, #{padding_meters})) AS bbox_w",
      "ST_XMax(ST_Expand(geom::geometry, #{padding_meters})) AS bbox_e",
      "ST_YMin(ST_Expand(geom::geometry, #{padding_meters})) AS bbox_s",
      "ST_YMax(ST_Expand(geom::geometry, #{padding_meters})) AS bbox_n"
    )
  }

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
    Routes::GeometryService.new(self).points
  end

  # Delegates to Routes::GeometryService — see app/services/routes/geometry_service.rb
  def boundaries
    Routes::GeometryService.new(self).boundaries
  end

  # Delegates to Routes::GeometryService — see app/services/routes/geometry_service.rb
  def closest_point_info(lat, lon)
    Routes::GeometryService.new(self).closest_point_info(lat, lon)
  end

  def self.find_by_waypoint(waypoint)
    Route.joins(%i[waypoint_start waypoint_end])
         .where("#{waypoint.sequence} BETWEEN waypoints.sequence AND waypoint_ends_routes.sequence")
         .first
  end

  private

  def enqueue_calculate_route
    CalculateRouteJob.perform_later(id)
  end

  def waypoints_changed?
    saved_change_to_waypoint_start_id? || saved_change_to_waypoint_end_id?
  end
end
