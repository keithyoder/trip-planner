# frozen_string_literal: true

module Follow
  # The day list for /follow. A route is a day, so each row is one route; the
  # calendar days between two routes that nobody drives (the date view skips
  # them) become dimmed rest-day rows, so the numbers read straight through.
  #
  # The list is shown a window at a time (SIZE rows) with the current day in the
  # middle, so a visitor sees what is around today and can page back and forth
  # through the whole trip. Before the trip starts the window opens on day 1;
  # after it ends, on the last day.
  #
  # Raises when a route has no computed date: that means the start_time chain
  # is broken (e.g. a route running backwards), and a day list that quietly
  # dropped it would hide the data bug.
  class Days
    Day = Struct.new(:route_id, :number, :date, :from, :to, :meters, :state, :rest, keyword_init: true) do
      def rest? = rest
    end
    # earlier/later are the day number to centre the previous/next window on, or
    # nil when there is nothing further that way.
    Result = Struct.new(:days, :current, :earlier, :later)

    SIZE = 11

    class Undated < StandardError; end

    # @param around [Integer, nil] day number to centre the window on; the current day when nil
    def initialize(trip, today: Landing::TripPhase.today, around: nil)
      @trip = trip
      @today = today
      @around = around
    end

    def call
      days = with_rest_days(route_days)
      current = days.find { |d| d.state == :today } || days.find { |d| d.state == :planned && !d.rest? } || days.last
      return Result.new([], current, nil, nil) if days.empty?

      window(days, current)
    end

    private

    def route_days
      sequences = @trip.route_sequences.order(:sequence).to_a
      routes = Route.without_geom.where(id: sequences.map(&:route_id))
                    .preload(:waypoint_start, :waypoint_end).index_by(&:id)
      undated = sequences.select { |rs| rs.start_time_sequence.nil? }
      raise Undated, "routes without a date: #{undated.map(&:route_id).join(', ')}" if undated.any?

      sequences.filter_map do |rs|
        route = routes.fetch(rs.route_id)
        next if route.skipped?

        build_day(rs.tap { |s| s.trip = @trip }, route)
      end
    end

    def build_day(sequence, route)
      Day.new(route_id: route.id, number: sequence.day, date: sequence.date,
              from: route.waypoint_start.name, to: route.waypoint_end.name,
              meters: sequence.distance.to_f, state: state_for(route, sequence.date), rest: false)
    end

    def state_for(route, date)
      return :done if route.completed?
      return :today if route.in_progress? || date == @today

      :planned
    end

    def with_rest_days(days)
      days.each_cons(2).with_object([days.first].compact) do |(prev, nxt), out|
        ((prev.number + 1)...nxt.number).each do |n|
          out << Day.new(number: n, date: prev.date + (n - prev.number), from: prev.to, to: prev.to,
                         meters: 0, state: nxt.state == :done ? :done : :planned, rest: true)
        end
        out << nxt
      end
    end

    # SIZE rows around the centre day. Near either end the window slides instead
    # of shrinking, so a page is always full when the trip has that many days.
    def window(days, current)
      centre = @around ? (days.index { |d| d.number >= @around } || days.size - 1) : days.index(current)
      start = (centre - SIZE / 2).clamp(0, [days.size - SIZE, 0].max)
      stop = start + SIZE
      earlier = start.positive? ? days[[start - SIZE / 2 - 1, 0].max].number : nil
      later = stop < days.size ? days[[stop + SIZE / 2, days.size - 1].min].number : nil
      Result.new(days[start, SIZE], current, earlier, later)
    end
  end
end
