# frozen_string_literal: true

class Trip < ApplicationRecord
  has_many :routes, dependent: :destroy
  has_many :route_sequences, through: :routes
  has_many :elevations, through: :routes, class_name: 'RouteElevation'
  has_many :waypoints, dependent: :destroy
  has_many :waypoint_distances, foreign_key: :trip_id, primary_key: :id
  has_one :track, class_name: 'TripTrack', foreign_key: :trip_id, primary_key: :id

  validates :name, presence: true

  def distance
    route_sequences.sum(:distance)
  end

  def waypoints_coordinates
    waypoints.map { |wp| [wp.lonlat.x, wp.lonlat.y] }
  end

  def calculate_route
    routes.each(&:calculate_route)
  end
end
