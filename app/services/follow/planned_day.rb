# frozen_string_literal: true

module Follow
  # Everything the read-only "planned day" page shows about one route: stats,
  # the stops with approximate times, the altitude profile, sun times and the
  # expected weather.
  #
  # It never calls an external service. Weather comes only from rows already
  # cached in WeatherEstimate (the admin route page prefetches them), because a
  # visitor's page load must not wait on, or trigger, a third-party request.
  # Without cached weather the weather blocks are simply absent.
  class PlannedDay
    Stop = Struct.new(:number, :time, :name, :type, :km, :delay_minutes, :temp_c, :lat, :lon, keyword_init: true)
    Sun = Struct.new(:dawn, :sunrise, :noon, :sunset, :dusk, :daylight, :driving_from, :driving_to, keyword_init: true)
    Weather = Struct.new(:max_c, :min_c, :rain_percent, :hourly, keyword_init: true)

    # Stop types that are not worth listing: routing points only shape the line.
    HIDDEN_TYPES = %w[routing toll_booth].freeze
    PROFILE_STEP_METERS = 200

    attr_reader :route, :sequence

    # @param route [Route] loaded with its geometry (the elevation profile needs it)
    def initialize(route)
      @route = route
      @sequence = route.route_sequence
      raise ArgumentError, "route #{route.id} has no date: the trip's start_time chain is broken" unless @sequence&.start_time_sequence

      raise ArgumentError, "route #{route.id} has no calculated segments yet" if route.segments.blank?

      @sequence.trip = route.trip
    end

    def number = sequence.day
    def date = sequence.date
    def from = route.waypoint_start.name
    def to = route.waypoint_end.name
    def km = (sequence.distance.to_f / 1000).round

    # Driving time, excluding stops, rounded to the minute by RouteSequence.
    def driving_minutes = (sequence.driving_duration.to_i / 60.0).round

    def day_plan_html(locale)
      MarkdownRenderer.render(route.day_plan&.dig(locale.to_s)).html_safe # rubocop:disable Rails/OutputSafety -- our own generated text
    end

    def stops
      @stops ||= timeline.reject { |entry| entry[:hidden] }.each_with_index.map do |entry, index|
        Stop.new(number: index + 1, time: entry[:arrival], name: entry[:waypoint].name, type: entry[:type],
                 km: entry[:km], delay_minutes: entry[:waypoint].delay.to_i / 60, temp_c: temp_at(entry),
                 lat: entry[:waypoint].lonlat.y.round(5), lon: entry[:waypoint].lonlat.x.round(5))
      end
    end

    # [[km, metres above sea level], ...], one point per PROFILE_STEP_METERS.
    def elevation_profile
      @elevation_profile ||= begin
        walked = 0.0
        previous = nil
        bucket = -1
        route.geom.points.each_with_object([]) do |point, profile|
          walked += previous.distance(point) if previous
          previous = point
          next unless (walked / PROFILE_STEP_METERS).floor > bucket

          bucket = (walked / PROFILE_STEP_METERS).floor
          profile << [(walked / 1000).round(2), point.z.to_f.round]
        end
      end
    end

    def max_altitude_m = elevation_profile.map(&:last).max

    # Leaflet wants [lat, lon]; thinned so the page does not carry every point.
    def line
      step = [route.geom.points.size / 400, 1].max
      route.geom.points.each_slice(step).map { |slice| [slice.first.y.round(5), slice.first.x.round(5)] }
    end

    def sun
      return @sun if defined?(@sun)

      @sun = build_sun
    end

    def weather
      return @weather if defined?(@weather)

      @weather = build_weather
    end

    def overnight = waypoints[1..].to_a.find(&:overnight?)
    def borders = timeline.select { |e| e[:type] == 'border_crossing' }
    def surfaces = route.significant_surfaces.first(3)

    # The previous/next day: neighbours by sequence within the same trip.
    def neighbours
      @neighbours ||= begin
        ids = route.trip.route_sequences.order(:sequence).pluck(:route_id)
        idx = ids.index(route.id)
        [idx&.positive? ? ids[idx - 1] : nil, idx ? ids[idx + 1] : nil]
      end
    end

    private

    def waypoints
      @waypoints ||= begin
        list = route.waypoints.to_a
        ActiveRecord::Associations::Preloader.new(
          records: list, associations: :boundaries, scope: Boundary.without_geom
        ).call
        list
      end
    end

    # One entry per waypoint with its approximate arrival (seconds from midnight,
    # as ORS durations accumulate from the route's start_time) and distance.
    def timeline
      @timeline ||= begin
        clock = route.start_time.to_f % 86_400
        metres = 0.0
        waypoints.each_with_index.map { |wp, i| entry_for(wp, i, clock, metres).tap { |e| clock, metres = e.values_at(:clock, :metres) } }
      end
    end

    def entry_for(waypoint, index, clock, metres)
      segment = index.positive? ? route.segments[index - 1] : nil
      clock += segment['duration'].to_f if segment
      metres += segment['distance'].to_f if segment
      type = if index.zero? then 'departure' elsif index == waypoints.size - 1 then 'arrival' else waypoint.waypoint_type end
      { waypoint: waypoint, type: type, arrival: clock, km: (metres / 1000).round, clock: clock + waypoint.delay.to_i,
        metres: metres, hidden: HIDDEN_TYPES.include?(type) }
    end

    def temp_at(entry)
      curve = curve_for(entry[:waypoint])
      curve&.at((entry[:arrival] / 3600).floor % 24)&.round
    end

    def estimate_for(waypoint)
      return unless waypoint.lonlat && date

      WeatherEstimate.for_location(waypoint.lonlat.y.to_f.round(2), waypoint.lonlat.x.to_f.round(2), date)&.to_weather_result
    end

    def curve_for(waypoint)
      @curves ||= {}
      return @curves[waypoint.id] if @curves.key?(waypoint.id)

      result = estimate_for(waypoint)
      @curves[waypoint.id] = result && ::Weather::HourlyTemperature.new(result, solar_for(waypoint))
    end

    def solar_for(waypoint)
      SolarPosition.new(date, waypoint.lonlat, waypoint.timezone || SolarPosition::DEFAULT_TIMEZONE)
    end

    def build_sun
      first = waypoints.first
      last = waypoints.last
      return unless first&.lonlat && last&.lonlat

      morning = solar_for(first)
      evening = solar_for(last)
      Sun.new(dawn: morning.dawn, sunrise: morning.sunrise, noon: evening.solar_noon, sunset: evening.sunset,
              dusk: evening.dusk, daylight: evening.day_length,
              driving_from: timeline.first[:arrival], driving_to: timeline.last[:arrival])
    end

    def build_weather
      last = waypoints.last
      result = estimate_for(last)
      return unless result

      curve = curve_for(last)
      Weather.new(max_c: result.temp_max_c&.round, min_c: result.temp_min_c&.round,
                  rain_percent: result.precip_probability&.round, hourly: curve&.all)
    end
  end
end
