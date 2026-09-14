module Stops
  class Detector
    def initialize(trip = nil)
      @trip = trip
    end

    def detect_for_date(date)
      trip_logs = scoped_trip_logs(date)
      return [] if trip_logs.size < 2

      trip_logs.each_cons(2).filter_map { |prev_log, next_log| find_or_create_stop(prev_log, next_log) }
    end

    # Re-runs detection for a date. Matches existing Stops by start_time
    # (stable -- it's set from the end of the preceding TripLog, which
    # doesn't move when new TripLogs get added later in the same gap).
    # Updates end_time if it's changed, since inserting a new TripLog
    # into what used to be one long gap shortens it. Preserves
    # name/stop_type/notes. Never deletes.
    def redetect_for_date(date)
      trip_logs = scoped_trip_logs(date)

      updated = []
      created = []

      trip_logs.each_cons(2) do |prev_log, next_log|
        existing = Stop.find_by(trip_id: trip&.id, start_time: prev_log.end_time)

        if existing
          if existing.end_time != next_log.start_time
            existing.update!(end_time: next_log.start_time)
            updated << existing
          end
        else
          stop = build_stop(prev_log, next_log)
          created << stop if stop
        end
      end

      { updated: updated, created: created }
    end

    private

    attr_reader :trip

    def scoped_trip_logs(date)
      scope = trip ? TripLog.where(trip_id: trip.id) : TripLog.where(trip_id: nil)
      scope.on_date(date).order(:start_time).to_a
    end

    def find_or_create_stop(prev_log, next_log)
      Stop.find_by(trip_id: trip&.id, start_time: prev_log.end_time) || build_stop(prev_log, next_log)
    end

    def build_stop(prev_log, next_log)
      location = prev_log.end_location || next_log.start_location
      return nil unless location

      Stop.create!(
        trip_id: trip&.id,
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
