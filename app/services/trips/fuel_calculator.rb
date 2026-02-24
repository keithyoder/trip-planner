# frozen_string_literal: true

module Trips
  class FuelCalculator
    def initialize(trip)
      @trip = trip
    end

    # Recalculates all gas stops on the trip.
    def calculate
      calculate_stops(gas_stops, previous_km: 0.0)
    end

    # Recalculates only the newly inserted gas stop and the one after it.
    def calculate_from(sequence)
      affected = gas_stops.select { |s| s.sequence >= sequence }.first(2)
      previous_stop = gas_stops.select { |s| s.sequence < sequence }.last

      calculate_stops(affected, previous_km: previous_stop&.trip_distance&.km || 0.0)
    end

    private

    def calculate_stops(stops, previous_km:)
      return [] unless @trip.fuel_consumption_l_per_100km.present?

      stops.each_with_object([]) do |gas_stop, updated|
        current_km = gas_stop.trip_distance.km
        gas_stop.waypoint.update!(toll: litres_for_segment(current_km - previous_km))
        updated << gas_stop.waypoint
        previous_km = current_km
      end
    end

    def gas_stops
      @gas_stops ||= @trip.waypoint_distances
                          .where(waypoint_type: :gas_station)
                          .order(:sequence)
    end

    def litres_for_segment(km)
      ((km / 100.0) * @trip.fuel_consumption_l_per_100km.to_f).round(1)
    end
  end
end
