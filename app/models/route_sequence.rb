# frozen_string_literal: true

# == Schema Information
#
# Table name: route_sequences
#
#  route_id            :bigint           primary key
#  trip_id             :bigint
#  sequence            :integer
#  route_name          :text
#  stopped_time        :interval
#  distance            :float
#  duration            :interval
#  start_time_sequence :interval
#
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

  # Driving time only — excludes stops, ferry crossings, and hiking legs.
  #
  # @return [ActiveSupport::Duration, nil]
  def driving_duration
    return unless duration.present?

    seconds = duration - (stopped_time || 0) - ferry_duration_seconds - hiking_duration_seconds
    ActiveSupport::Duration.build(round_duration_to_minute(seconds))
  end

  # Time spent on ferry crossings for this route.
  #
  # @return [ActiveSupport::Duration, nil]
  def ferry_duration
    return unless duration.present?

    ActiveSupport::Duration.build(round_duration_to_minute(ferry_duration_seconds))
  end

  # Time spent on foot-hiking legs for this route.
  #
  # @return [ActiveSupport::Duration, nil]
  def hiking_duration
    return unless duration.present?

    ActiveSupport::Duration.build(round_duration_to_minute(hiking_duration_seconds))
  end

  # Total duration including driving, stops, ferry, and hiking.
  #
  # @return [ActiveSupport::Duration, nil]
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

  private

  def ferry_duration_seconds
    @ferry_duration_seconds ||= route.leg_duration_for(&:ferry_disembarkment?)
  end

  def hiking_duration_seconds
    @hiking_duration_seconds ||= route.leg_duration_for { |wp| wp.profile.start_with?('foot-') }
  end
end
