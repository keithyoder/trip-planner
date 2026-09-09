# frozen_string_literal: true

module Stops
  # Finds gaps between consecutive TripLogs belonging to the same Trip and
  # persists them as Stop records -- the inverse of TripDetector's trip
  # segmentation. Every gap qualifies automatically: TripDetector only
  # splits driving into separate TripLogs when stationary for at least
  # max_stop_duration (300s), so the gap between any two saved TripLogs is
  # already guaranteed to meet that bar -- no separate threshold needed
  # here.
  #
  # Idempotent: re-running only creates Stops for gaps that don't already
  # have one (matched on trip_id + start_time, backed by the unique index
  # on stops), so it's safe to call repeatedly as new TripLogs land.
  class Detector
    def initialize(trip)
      @trip = trip
    end

    # @param date [Date]
    # @return [Array<Stop>] stops for every gap that day (pre-existing
    #   ones included, so callers get the full picture)
    def detect_for_date(date)
      trip_logs = TripLog.where(trip_id: trip.id).on_date(date).order(:start_time).to_a
      return [] if trip_logs.size < 2

      trip_logs.each_cons(2).filter_map do |prev_log, next_log|
        find_or_create_stop(prev_log, next_log)
      end
    end

    private

    attr_reader :trip

    def find_or_create_stop(prev_log, next_log)
      existing = Stop.find_by(trip_id: trip.id, start_time: prev_log.end_time)
      return existing if existing

      location = prev_log.end_location || next_log.start_location
      return nil unless location

      Stop.create!(
        trip_id: trip.id,
        start_time: prev_log.end_time,
        end_time: next_log.start_time,
        geom: RGeo::Geographic.spherical_factory(srid: 4326).point(location[:lon], location[:lat])
      )
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.warn("[Stops::Detector] failed to create stop: #{e.message}")
      nil
    end
  end
end
