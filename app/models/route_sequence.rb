# frozen_string_literal: true

class RouteSequence < ActiveRecord::Base
  belongs_to :route
  has_one :trip, through: :route, foreign_key: :route_trip_id, primary_key: :trip_id
  attribute :distance, :distance

  self.primary_key = :route_id

  # Allow manually setting the trip to avoid N+1 queries
  attr_writer :trip

  def readonly?
    true
  end

  def driving_duration
    ActiveSupport::Duration.build(round_duration_to_minute(duration - (stopped_time || 0))) if duration.present?
  end

  def total_duration
    ActiveSupport::Duration.build(round_duration_to_minute(duration)) if duration.present?
  end

  def round_duration_to_minute(duration)
    (duration / 60).round * 60 if duration.present?
  end

  def day
    (start_time_sequence.parts[:days] || 0) + 1
  end

  def date
    trip.start_on + day.days if trip.start_on.present?
  end

  # Override trip method to use manually set trip if available
  def trip
    @trip || super
  end
end
