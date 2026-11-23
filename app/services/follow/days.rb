# frozen_string_literal: true

module Follow
  # The day list for /follow. A route is a day, so each row is one route; the
  # calendar days between two routes that nobody drives (the date view skips
  # them) become dimmed rest-day rows, so the numbers read straight through.
  #
  # Rows are grouped by the country the day ends in. Countries after the one
  # we are in (or about to enter) collapse into the "Later" summary, so a
  # visitor sees the stretch that matters first.
  #
  # Raises when a route has no computed date: that means the start_time chain
  # is broken (e.g. a route running backwards), and a day list that quietly
  # dropped it would hide the data bug.
  class Days
    Day = Struct.new(:route_id, :number, :date, :from, :to, :country, :km, :state, :rest, keyword_init: true) do
      def rest? = rest
    end
    Group = Struct.new(:country, :days)
    Later = Struct.new(:country, :total)
    Result = Struct.new(:groups, :later, :current)

    class Undated < StandardError; end

    def initialize(trip, today: Landing::TripPhase.today)
      @trip = trip
      @today = today
    end

    def call
      days = with_rest_days(route_days)
      current = days.find { |d| d.state == :today } || days.find { |d| d.state == :planned && !d.rest? }
      groups = days.chunk_while { |a, b| a.country == b.country }.map { |chunk| Group.new(chunk.first.country, chunk) }
      shown, later = split_later(groups, current)
      Result.new(shown, later.map { |g| Later.new(g.country, g.days.size) }, current)
    end

    private

    def route_days
      sequences = @trip.route_sequences.order(:sequence).to_a
      routes = Route.without_geom.where(id: sequences.map(&:route_id))
                    .preload(:waypoint_start, :waypoint_end).index_by(&:id)
      countries = arrival_countries(routes.values)
      undated = sequences.select { |rs| rs.start_time_sequence.nil? }
      raise Undated, "routes without a date: #{undated.map(&:route_id).join(', ')}" if undated.any?

      sequences.filter_map do |rs|
        route = routes.fetch(rs.route_id)
        next if route.skipped?

        build_day(rs.tap { |s| s.trip = @trip }, route, countries[route.waypoint_end_id])
      end
    end

    def build_day(sequence, route, country)
      Day.new(route_id: route.id, number: sequence.day, date: sequence.date,
              from: route.waypoint_start.name, to: route.waypoint_end.name, country: country,
              km: (sequence.distance.to_f / 1000).round, state: state_for(route, sequence.date), rest: false)
    end

    def state_for(route, date)
      return :done if route.completed?
      return :today if route.in_progress? || date == @today

      :planned
    end

    # Boundaries carry heavy multipolygons: preload without geometry, never includes.
    def arrival_countries(routes)
      waypoints = routes.map(&:waypoint_end).uniq
      ActiveRecord::Associations::Preloader.new(
        records: waypoints, associations: :boundaries, scope: Boundary.without_geom
      ).call
      waypoints.to_h { |wp| [wp.id, wp.country.presence] }
    end

    def with_rest_days(days)
      days.each_cons(2).with_object([days.first].compact) do |(prev, nxt), out|
        ((prev.number + 1)...nxt.number).each do |n|
          out << Day.new(number: n, date: prev.date + (n - prev.number), from: prev.to, to: prev.to,
                         country: prev.country, km: 0, state: nxt.state == :done ? :done : :planned, rest: true)
        end
        out << nxt
      end
    end

    def split_later(groups, current)
      return [groups, []] unless current

      idx = groups.index { |g| g.days.include?(current) }
      [groups.first(idx + 1), groups.drop(idx + 1)]
    end
  end
end
