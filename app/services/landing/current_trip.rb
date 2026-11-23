# frozen_string_literal: true

module Landing
  # The trip the landing page talks about: the one underway, otherwise the next
  # one still to start, otherwise the most recent one that finished.
  class CurrentTrip
    def self.find(today: TripPhase.today)
      Trip.current ||
        Trip.planning.where(start_on: today..).order(:start_on).first ||
        Trip.completed.order(start_on: :desc).first
    end
  end
end
