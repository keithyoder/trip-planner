# frozen_string_literal: true

module Landing
  # The trip the landing page talks about: the one underway, otherwise the next
  # one still to start, otherwise the most recent one that has started.
  #
  # That last step also covers a trip whose start date has passed but whose
  # status was never flipped from planning: it still shows as "day N" instead of
  # leaving the page with nothing to talk about.
  class CurrentTrip
    def self.find(today: TripPhase.today)
      Trip.current ||
        Trip.planning.where(start_on: today..).order(:start_on).first ||
        Trip.where.not(status: :skipped).order(start_on: :desc).first
    end
  end
end
