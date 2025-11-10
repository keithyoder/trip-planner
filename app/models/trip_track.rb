# frozen_string_literal: true

# == Schema Information
#
# Table name: trip_tracks
#
#  trip_id  :bigint           primary key
#  geom     :geography        geometry, 0
#  distance :float
#
class TripTrack < ApplicationRecord
  belongs_to :trip
  attribute :distance, :distance
  attribute :geom, :multi_line_string, srid: 4326, geographic: true, has_z: true

  self.primary_key = :trip_id

  def readonly?
    true
  end

  def coordinates # rubocop:disable Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
    coords = geom&.coordinates || []
    if coords.first.is_a?(Array) && coords.first.first.is_a?(Array)
      coords.map do |line|
        line.map { |coord| [coord[1], coord[0]] }
      end
    else
      coords.map { |coord| [coord[1], coord[0]] }
    end
  end
end
