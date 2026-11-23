# frozen_string_literal: true

module Landing
  # Kilometres for the landing page: how far the planned route is and how far we
  # have driven. All figures are rounded the way the page shows them.
  class TripDistances
    # Used before any route has been planned, so the page still has a number.
    DEFAULT_PLANNED_KM = 30_000

    def initialize(trip)
      @trip = trip
    end

    # Length of the planned route, to the nearest 100 km. This is the real
    # route (the sum of its legs), so it will differ from any round number
    # quoted in copy; the fallback applies only while no route is planned.
    def planned_km
      @planned_km ||= begin
        meters = @trip.route_sequences.sum(:distance).to_f
        meters.positive? ? (meters / 1000.0 / 100).round * 100 : DEFAULT_PLANNED_KM
      end
    end

    # Driven so far, from the telemetry segments logged since the trip started.
    # TripLog has no trip_id, so the trip is identified by its start date,
    # taken in Pesqueira's zone so a late-night departure isn't cut off.
    def driven_km
      @driven_km ||= (driven_meters / 1000.0).round
    end

    # What remains, to the nearest 100 km, and never negative (detours can make
    # the odometer pass the plan).
    def left_km
      [((planned_km - driven_km) / 100.0).round * 100, 0].max
    end

    def percent
      return 0 unless planned_km.positive?

      (driven_km * 100.0 / planned_km).round.clamp(0, 100)
    end

    private

    def driven_meters
      from = Time.find_zone!(TripPhase::ZONE).local(@trip.start_on.year, @trip.start_on.month, @trip.start_on.day)
      TripLog.where(start_time: from..).sum(Arel.sql('ST_Length(geom::geography)')).to_f
    end
  end
end
