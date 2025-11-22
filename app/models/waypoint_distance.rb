# frozen_string_literal: true

# == Schema Information
#
# Table name: waypoint_distances
#
#  id               :bigint           primary key
#  name             :string
#  address          :string
#  sequence         :integer
#  lonlat           :geography        point, 4326
#  created_at       :datetime
#  updated_at       :datetime
#  waypoint_type    :integer
#  toll             :decimal(, )
#  delay            :integer
#  osm_poi_id       :bigint
#  trip_id          :bigint
#  segment_distance :float
#  trip_distance    :float
#
class WaypointDistance < ActiveRecord::Base
  has_one :waypoint, foreign_key: :id
  has_one :trip, foreign_key: :id, primary_key: :trip_id
  has_many :boundaries, through: :waypoint
  attribute :trip_distance, :distance
  attribute :segment_distance, :distance

  delegate :waypoint_type, :location, :country, :currency, to: :waypoint

  self.primary_key = :id

  enum :waypoint_type, {
    overnight: 1,
    lunch: 2,
    ferry_boarding: 3,
    ferry_disembarkment: 4,
    toll_booth: 5,
    border_crossing: 6,
    gas_station: 7
  }

  def readonly?
    true
  end

  def self.calculate_fuel(trip_id)
    trip = Trip.find(trip_id)
    return unless trip.fuel_consumption_l_per_100km.present?

    previous_km = 0
    trip.waypoint_distances.where(waypoint_type: :gas_station).order(:sequence).each do |gas_stop|
      kms = gas_stop.trip_distance.km - previous_km
      puts kms
      puts (kms / 100 * trip.fuel_consumption_l_per_100km.to_f).round(1)
      gas_stop.waypoint.update(toll: (kms / 100 * trip.fuel_consumption_l_per_100km.to_f).round(1))
      previous_km = gas_stop.trip_distance.km
    end
  end
end
