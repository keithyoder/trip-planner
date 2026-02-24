# frozen_string_literal: true

# == Schema Information
#
# Table name: trips
#
#  id         :bigint           not null, primary key
#  name       :string
#  start_on   :date
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
class Trip < ApplicationRecord
  has_many :routes, dependent: :destroy
  has_many :route_sequences, through: :routes
  # has_many :elevations, through: :routes, class_name: 'RouteElevation'
  has_many :waypoints, dependent: :destroy
  has_many :waypoint_distances, foreign_key: :trip_id, primary_key: :id
  has_one :track, class_name: 'TripTrack', foreign_key: :trip_id, primary_key: :id

  attribute :fuel_consumption_l_per_100km, :fuel_consumption
  attribute :distance, :distance

  validates :name, presence: true

  scope :with_distance, lambda {
    select(
      'trips.*',
      '(SELECT SUM(route_sequences.distance)
        FROM route_sequences
        INNER JOIN routes ON route_sequences.route_id = routes.id
        WHERE routes.trip_id = trips.id) AS distance'
    )
  }

  scope :with_duration, lambda {
    select(
      'trips.*',
      '((SELECT trips.start_on + (EXTRACT(DAY FROM route_sequences.start_time_sequence)::integer + 1)
       FROM route_sequences
       INNER JOIN routes ON route_sequences.route_id = routes.id
       WHERE routes.trip_id = trips.id
       ORDER BY route_sequences.sequence DESC
       LIMIT 1) - trips.start_on - 1) AS duration_days'
    )
  }

  def waypoints_coordinates
    waypoints.map { |wp| [wp.lonlat.x, wp.lonlat.y] }
  end

  def calculate_route
    routes.each(&:calculate_route)
  end
end
