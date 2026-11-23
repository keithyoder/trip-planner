# frozen_string_literal: true

module Landing
  # Which state the landing page's trip counter is in, and the number to show.
  #
  # The switch to "home" is the trip's `completed` status, which is set by hand
  # (never a fixed return date: the trip has no promised end). Everything else
  # follows from the start date.
  #
  #   :before  days until the start date
  #   :today   the day we leave
  #   :during  day N of the trip
  #   :home    day N of the trip, now back (the total stays as the final count)
  class TripPhase
    # Pesqueira's zone (UTC-3, no daylight saving). Fixed on purpose: the day
    # count must not change with the server's zone or the visitor's, and the
    # trip crosses several zones, so "today" is always counted in Pernambuco.
    ZONE = 'America/Recife'

    def self.today
      Time.find_zone!(ZONE).today
    end

    def initialize(trip, today: self.class.today)
      @trip = trip
      @today = today
    end

    def phase
      return :home if @trip.completed?

      case days_until_start
      when 1.. then :before
      when 0 then :today
      else :during
      end
    end

    # Days until we leave (before) or the 1-based day of the trip (during/home).
    # Meaningless on the start day itself, where the page says "Today".
    def days
      return days_until_start if phase == :before

      [(@today - @trip.start_on).to_i + 1, 1].max
    end

    private

    def days_until_start
      (@trip.start_on - @today).to_i
    end
  end
end
