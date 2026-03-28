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

  # Allow manually setting the trip, route, and preloaded waypoints to avoid N+1 queries
  attr_writer :trip
  attr_writer :route, :preloaded_waypoints

  def readonly?
    true
  end

  # Driving time only — excludes stops, ferry crossings, hiking, and transit legs.
  #
  # @return [ActiveSupport::Duration, nil]
  def driving_duration
    return unless duration.present?

    seconds = duration - (stopped_time || 0) - ferry_duration_seconds - hiking_duration_seconds - transit_duration_seconds
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

  # Time spent on transit legs for this route.
  #
  # @return [ActiveSupport::Duration, nil]
  def transit_duration
    return unless duration.present?

    ActiveSupport::Duration.build(round_duration_to_minute(transit_duration_seconds))
  end

  # Total duration including driving, stops, ferry, hiking, and transit.
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
    trip.start_on + start_time_sequence.parts[:days].to_i.days if trip.start_on.present?
  end

  # Override association readers to use manually assigned values when available,
  # avoiding N+1 queries when preloaded in the controller.
  def trip
    @trip || super
  end

  def route
    @route || super
  end

  private

  def ferry_duration_seconds
    @ferry_duration_seconds ||= route.leg_duration_for(
      preloaded_waypoints: @preloaded_waypoints,
      &:ferry_disembarkment?
    )
  end

  def hiking_duration_seconds
    @hiking_duration_seconds ||= route.leg_duration_for(
      preloaded_waypoints: @preloaded_waypoints
    ) { |wp| wp.profile.start_with?('foot-') }
  end

  def transit_duration_seconds
    @transit_duration_seconds ||= route.leg_duration_for(
      preloaded_waypoints: @preloaded_waypoints,
      &:transit?
    )
  end
end
