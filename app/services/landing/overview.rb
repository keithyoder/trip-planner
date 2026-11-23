# frozen_string_literal: true

module Landing
  # Everything the landing page shows about the trip, computed on the server so
  # the page is right on first load: the counter state, the km figures and the
  # hero map.
  #
  # The map is cached for a day. Its key includes today's date (in Pesqueira), so
  # it refreshes itself the first time anyone loads the page after midnight; a
  # miss simply computes it then. `refresh_map!` (the landing:refresh_map rake
  # task) rebuilds it on demand, e.g. from cron, so no visitor pays for it.
  class Overview
    class NoTripError < StandardError; end

    CACHE_VERSION = 'v1'
    MAP_TTL = 2.days

    attr_reader :trip, :today

    def self.build(today: TripPhase.today)
      trip = CurrentTrip.find(today: today)
      raise NoTripError, 'No trip to show on the landing page: create a trip with a start date' unless trip

      new(trip, today: today)
    end

    def initialize(trip, today:)
      @trip = trip
      @today = today
    end

    delegate :start_on, to: :trip
    delegate :phase, :days, to: :trip_phase
    delegate :planned_km, :driven_km, :left_km, :percent, to: :distances

    def map
      Rails.cache.fetch(map_cache_key, expires_in: MAP_TTL) { build_map }
    end

    def refresh_map!
      Rails.cache.write(map_cache_key, build_map, expires_in: MAP_TTL)
    end

    private

    def trip_phase
      @trip_phase ||= TripPhase.new(trip, today: today)
    end

    def distances
      @distances ||= TripDistances.new(trip)
    end

    def build_map
      # The share already driven only breaks ties between passes of the same
      # place on a looping route; see RouteRemainder.
      fraction = planned_km.positive? ? driven_km.to_f / planned_km : 0.0
      RouteMap.new(trip, phase: phase, driven_fraction: fraction).build
    end

    def map_cache_key
      ['landing/route_map', CACHE_VERSION, trip.id, today.iso8601, phase]
    end
  end
end
