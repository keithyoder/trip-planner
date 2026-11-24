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
    Stop = Struct.new(:number, :time, :name, :type, :meters, :delay_minutes, :temp_c, :lat, :lon, keyword_init: true)
    Sun = Struct.new(:dawn, :sunrise, :noon, :sunset, :dusk, :daylight, :driving_from, :driving_to, keyword_init: true)
    Peak = Struct.new(:altitude_m, :meters, :places, keyword_init: true)
    Weather = Struct.new(:max_c, :min_c, :rain_percent, :hourly, :band, keyword_init: true)

    # Stop types that are not worth listing: routing points only shape the line.
    HIDDEN_TYPES = %w[routing toll_booth].freeze
    PROFILE_STEP_METERS = 200

    attr_reader :route, :sequence

    # @param route [Route] loaded with its geometry (the elevation profile needs it)
    def initialize(route)
      @route = route
      @sequence = route.route_sequence
      unless @sequence&.start_time_sequence
        raise ArgumentError, "route #{route.id} has no date: the trip's start_time chain is broken"
      end

      raise ArgumentError, "route #{route.id} has no calculated segments yet" if route.segments.blank?

      @sequence.trip = route.trip
    end

    def number = sequence.day
    def date = sequence.date
    def from = route.waypoint_start.name
    def to = route.waypoint_end.name
    def meters = sequence.distance.to_f

    # Driving time, excluding stops, rounded to the minute by RouteSequence.
    def driving_minutes = (sequence.driving_duration.to_i / 60.0).round

    # The plan is what we wrote in the waypoint notes (the same text the admin
    # route page shows), falling back to the generated narrative. Notes first: they
    # are plain prose, whereas the generated text carries its own headings.
    # Tries the visitor's language, then the app default, so a plan written in
    # one language still shows.
    def day_plan_html(locale)
      markdown = [locale.to_s, I18n.default_locale.to_s].uniq.each do |code|
        text = plan_notes(code) || route.day_plan&.dig(code).presence
        break text if text
      end
      # html_safe is fine here: the markdown is our own notes, rendered by MarkdownRenderer.
      markdown.is_a?(String) ? MarkdownRenderer.render(markdown).html_safe : ''
    end

    def stops
      @stops ||= timeline.reject { |entry| entry[:hidden] }.each_with_index.map do |entry, index|
        Stop.new(number: index + 1, time: entry[:arrival], name: entry[:waypoint].name, type: entry[:type],
                 meters: entry[:metres], delay_minutes: entry[:waypoint].delay.to_i / 60, temp_c: temp_at(entry),
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

    def max_altitude_m = peak&.altitude_m

    # The highest point of the day: how far from the start, and which region and
    # country it is in. Measured on the full-resolution line rather than the 200 m
    # profile, so a narrow pass is not missed.
    def peak
      return @peak if defined?(@peak)

      @peak = build_peak
    end

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

    # The previous/next day as [route_id, day_number] (nil at the ends): neighbours
    # by sequence within the same trip. The number is for the link label, and can
    # skip one when a rest day sits between the two.
    def neighbours
      @neighbours ||= begin
        pairs = route.trip.route_sequences.order(:sequence).map do |rs|
          rs.trip = route.trip
          [rs.route_id, rs.day]
        end
        idx = pairs.index { |id, _| id == route.id }
        [idx&.positive? ? pairs[idx - 1] : nil, idx ? pairs[idx + 1] : nil]
      end
    end

    private

    def plan_notes(locale)
      DayPlanPresenter.new(route, locale: locale).notes_markdown
    end

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
        waypoints.each_with_index.map do |wp, i|
          entry = entry_for(wp, i, clock, metres)
          clock = entry[:clock]
          metres = entry[:metres]
          entry
        end
      end
    end

    def entry_for(waypoint, index, clock, metres)
      segment = index.positive? ? route.segments[index - 1] : nil
      clock += segment['duration'].to_f if segment
      metres += segment['distance'].to_f if segment
      type = if index.zero?
               'departure'
             elsif index == waypoints.size - 1
               'arrival'
             else
               waypoint.waypoint_type
             end
      { waypoint: waypoint, type: type, arrival: clock, clock: clock + waypoint.delay.to_i,
        metres: metres, hidden: HIDDEN_TYPES.include?(type) }
    end

    def temp_at(entry)
      curve = curve_for(entry[:waypoint])
      curve&.at((entry[:arrival] / 3600).floor % 24)
    end

    def estimate_for(waypoint)
      return unless waypoint.lonlat && date

      WeatherEstimate.for_location(waypoint.lonlat.y.to_f.round(2), waypoint.lonlat.x.to_f.round(2),
                                   date)&.to_weather_result
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

    def build_peak
      walked = 0.0
      previous = nil
      best = nil
      route.geom.points.each do |point|
        walked += previous.distance(point) if previous
        previous = point
        best = [point, walked] if best.nil? || point.z.to_f > best[0].z.to_f
      end
      return unless best

      point, metres = best
      # Region (level 4) then country (level 2); without_geom because boundaries
      # carry heavy multipolygons we only need the names of.
      places = Boundary.without_geom.containing_point(point.y, point.x).order(level: :desc).map(&:name)
      Peak.new(altitude_m: point.z.to_f.round, meters: metres, places: places)
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

    # The day's weather is one curve that follows the car from waypoint to
    # waypoint. Each waypoint with a cached estimate has its own hourly curve;
    # while the car is at a waypoint the chart follows that curve, and between
    # two waypoints it fades from one curve to the next in proportion to the
    # driving time elapsed. Nothing is looked up between waypoints: the places
    # on the curve are exactly the places we have estimates for, so a day that
    # drops from the altiplano to the coast shows the change instead of the
    # arrival point's weather all day.
    def build_weather
      stays = weather_stays
      return if stays.empty?

      hourly = blend(stays) { |stay, hour| stay[:curve].at(hour) }
      band = band_curves(stays)&.then do |bounds|
        bounds.transform_values { |key| blend(stays) { |stay, hour| stay[:bounds][key].at(hour) } }
      end
      rain = stays.filter_map { |stay| stay[:result].precip_probability }.max
      Weather.new(max_c: hourly.values.max, min_c: hourly.values.min, rain_percent: rain&.round, hourly: hourly,
                  band: band)
    end

    # The timeline's waypoints that have weather, with when the car arrives and leaves.
    def weather_stays
      timeline.filter_map do |entry|
        result = estimate_for(entry[:waypoint])
        next unless result

        { arrival: entry[:arrival], departure: entry[:clock], result: result, curve: curve_for(entry[:waypoint]),
          waypoint: entry[:waypoint] }
      end
    end

    # One value per hour of the day from the stays' own curves. The block returns
    # a stay's value at an hour.
    def blend(stays)
      (0..23).to_h do |hour|
        seconds = hour * 3600
        [hour, blended_value(stays, seconds) { |stay| yield(stay, hour) }]
      end
    end

    def blended_value(stays, seconds)
      stays.each_cons(2) do |before, after|
        return yield(before) if seconds <= before[:departure]
        next if seconds >= after[:arrival]

        share = (seconds - before[:departure]) / (after[:arrival] - before[:departure])
        return (yield(before) * (1 - share)) + (yield(after) * share)
      end
      seconds >= stays.last[:arrival] ? yield(stays.last) : yield(stays.first)
    end

    # The expected range around the curve, as on the admin waypoint chart: one
    # standard deviation either side of each climate normal's daily min and max.
    # Only climate normals carry the deviations, so a day with any waypoint
    # lacking them (a forecast) gets no band rather than a half-true one.
    # Returns { warm: :warm, cold: :cold } after attaching the bound curves to
    # each stay, or nil.
    def band_curves(stays)
      return unless stays.all? { |stay| band_possible?(stay[:result]) }

      stays.each do |stay|
        stay[:bounds] = { warm: bound_curve(stay, 1), cold: bound_curve(stay, -1) }
      end
      { warm: :warm, cold: :cold }
    end

    def band_possible?(result)
      result.climate_normal? && result.temp_min_std.present? && result.temp_max_std.present?
    end

    def bound_curve(stay, factor)
      result = stay[:result]
      shifted = ::Weather::Result.new(
        temp_min: Units::Temperature.new(result.temp_min_c + (factor * result.temp_min_std), units: :celsius),
        temp_max: Units::Temperature.new(result.temp_max_c + (factor * result.temp_max_std), units: :celsius),
        source: :climate_normal
      )
      ::Weather::HourlyTemperature.new(shifted, solar_for(stay[:waypoint]))
    end
  end
end
