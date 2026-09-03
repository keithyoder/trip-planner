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
  has_many :trip_expenses, dependent: :destroy
  has_many :waypoints, dependent: :destroy
  has_many :waypoint_distances, foreign_key: :trip_id, primary_key: :id
  has_one :track, class_name: 'TripTrack', foreign_key: :trip_id, primary_key: :id
  has_many :coverage_features, class_name: 'NetworkCoverage::Feature', dependent: :destroy

  attribute :fuel_consumption_l_per_100km, :fuel_consumption
  attribute :distance, :distance

  validates :name, presence: true
  validate :only_one_in_progress_trip, if: :in_progress?

  enum :status, { planning: 0, in_progress: 1, completed: 2 }, default: :planning

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

  def self.current
    find_by(status: :in_progress)
  end

  def current_route
    routes.find_by(status: :in_progress)
  end

  private

  def only_one_in_progress_trip
    return unless Trip.where(status: :in_progress).where.not(id: id).exists?

    errors.add(:status, 'another trip is already in progress')
  end
end
