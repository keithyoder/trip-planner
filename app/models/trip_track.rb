# frozen_string_literal: true

class TripTrack < ApplicationRecord
  belongs_to :trip
  attribute :distance, :distance
  attribute :geom, :multi_line_string, srid: 4326, geographic: true, has_z: true

  self.primary_key = :trip_id

  def readonly?
    true
  end
end
