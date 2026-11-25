# frozen_string_literal: true

require 'builder' # Rails only loads it lazily, so outside a request it is missing

module Trips
  # Exports a trip's full route geometry as GPX 1.1 document(s), including:
  #
  #   - <trk>/<trkseg> per day (RouteSequence) with real elevation and
  #     timestamps that account for stops, ferries, and overnights
  #   - <wpt> markers for each named waypoint along the way, deduped within
  #     a document (a day's arrival point is often the next day's departure
  #     point)
  #
  # Timestamps: route_sequence.start_time_sequence + a route's geom M value
  # produce the intended local wall-clock digits at that route's location
  # (waypoint delays are already baked into M by Routing::DurationImporter,
  # and start_time_sequence already accounts for cross-route/overnight gaps
  # via the route_sequences view). Those digits are re-anchored to the
  # route's real IANA timezone (looked up from the Boundary containing its
  # start coordinate) so the emitted <time> carries a correct UTC offset
  # instead of a false 'Z' — otherwise viewers like Mapdirector re-shift the
  # displayed time by their own local offset.
  #
  # Stop holds: a mid-route waypoint with a delay gets a duplicate track
  # point at the same coordinates, timestamped at departure (arrival +
  # delay), so animators hold position for the stop instead of creeping
  # across the gap.
  #
  # See #to_gpx_files for splitting large trips into multiple <= 9MB files,
  # or #to_daily_gpx_files for one GPX document per day.
  #
  class GpxExporter
    MAX_BYTES = 9 * 1000 * 1000 # 9 MB

    # tolerance_m: when set, each day's track is thinned with Douglas-Peucker so
    # no dropped point lies farther than this from the line that replaces it.
    # Surviving points keep their own timestamps, so speed and stop timing are
    # preserved; only the shape between them is straightened. nil keeps every point.
    def initialize(trip, tolerance_m: nil)
      @trip = trip
      @tolerance_m = tolerance_m
    end

    # Single-file export. May exceed MAX_BYTES for large trips — prefer
    # to_gpx_files or to_daily_gpx_files for anything that needs to stay
    # under a size limit.
    #
    # @return [String] GPX 1.1 XML document
    def to_gpx
      days = route_sequences.filter_map { |rs| build_day(rs) }
      wrap_days(days)
    end

    # Splits the trip into multiple GPX documents, each <= MAX_BYTES,
    # never splitting a single day's <trk> across files.
    #
    # @return [Array<String>] one GPX document per chunk
    def to_gpx_files
      overhead      = wrap_days([]).bytesize
      chunks        = []
      current_days  = []
      current_size  = overhead

      route_sequences.each do |rs|
        day = build_day(rs)
        next unless day

        day_bytes = day_bytesize(day)

        if day_bytes + overhead > MAX_BYTES
          Rails.logger.warn(
            "[GpxExporter] route_sequence #{rs.route_id} alone exceeds " \
            "MAX_BYTES (#{day_bytes} bytes) — emitting as its own oversized file"
          )
        end

        if current_days.any? && current_size + day_bytes > MAX_BYTES
          chunks << wrap_days(current_days)
          current_days = []
          current_size = overhead
        end

        current_days << day
        current_size += day_bytes
      end

      chunks << wrap_days(current_days) if current_days.any?
      chunks
    end

    # One GPX document per RouteSequence (day). Naturally small, and
    # sidesteps any file-size limit entirely since each day's geometry is
    # tiny compared to the whole trip.
    #
    # @return [Array<Hash>] { route_sequence:, gpx: } — route_sequence
    #   included so callers can build sensible filenames (date, day number,
    #   route name)
    def to_daily_gpx_files
      route_sequences.filter_map do |rs|
        day = build_day(rs)
        next unless day

        { route_sequence: rs, gpx: wrap_days([day]) }
      end
    end

    private

    def route_sequences
      @route_sequences ||= @trip.route_sequences
                                .includes(:route)
                                .order(:sequence)
                                .to_a
                                .each { |rs| rs.trip = @trip } # avoid N+1 on rs.date
    end

    # Gathers everything needed to render one day: the <trk> fragment plus
    # a { waypoint_id => <wpt> fragment } hash for later cross-day dedup.
    def build_day(route_sequence)
      route       = route_sequence.route
      coordinates = safe_coordinates(route)
      return nil if coordinates.blank?

      route_start = trip_start + route_sequence.start_time_sequence
      zone        = route_timezone(route)
      waypoints   = route.waypoints.to_a
      stop_delays = stop_delays_by_index(waypoints, route.segments)
      arrivals    = waypoint_arrivals(waypoints, route.segments)
      # Stops and arrivals are what the timestamps hinge on: never thin them away.
      kept        = kept_indices(coordinates, stop_delays.keys + arrivals.values)

      {
        track_xml: build_track_xml(route_sequence, coordinates, route_start, zone, stop_delays, kept),
        wpt_xmls: build_waypoint_xmls(waypoints, arrivals, coordinates, route_start, zone)
      }
    end

    def day_bytesize(day)
      day[:track_xml].bytesize + day[:wpt_xmls].values.sum(&:bytesize)
    end

    def safe_coordinates(route)
      route&.geom&.coordinates
    rescue RGeo::Error::InvalidGeometry
      Rails.logger.warn("[GpxExporter] route #{route.id} has invalid geometry — skipping")
      nil
    end

    def build_track_xml(route_sequence, coordinates, route_start, zone, stop_delays, kept)
      xml = Builder::XmlMarkup.new(indent: 2)
      xml.trk do
        xml.name(track_name(route_sequence))
        xml.trkseg do
          coordinates.each_with_index do |coord, idx|
            next unless kept.include?(idx)

            build_point(xml, coord, route_start, zone)

            delay = stop_delays[idx]
            next unless delay&.positive?

            # Duplicate point at the same location, timestamped at
            # departure, so the animator holds position for the stop
            # instead of creeping across the gap to the next point.
            lon, lat, ele, m = coord
            build_point(xml, [lon, lat, ele, m.to_f + delay], route_start, zone)
          end
        end
      end
      xml.target!
    end

    # Indices of the points to emit: all of them, or the Douglas-Peucker
    # survivors plus the pinned ones (each pin splits the line, so the
    # simplification runs between pins and can never move them).
    def kept_indices(coordinates, pinned)
      last = coordinates.size - 1
      return (0..last).to_set unless @tolerance_m

      stops = ([0, last] + pinned).select { |i| i.between?(0, last) }.uniq.sort
      stops.each_cons(2).each_with_object(stops.to_set) do |(from, to), kept|
        simplify_range(coordinates, from, to, kept)
      end
    end

    # Iterative Douglas-Peucker over coordinates[from..to], adding survivors to kept.
    def simplify_range(coordinates, from, to, kept)
      queue = [[from, to]]
      until queue.empty?
        a, b = queue.pop
        next if b - a < 2

        index, distance = farthest_from_chord(coordinates, a, b)
        next if distance <= @tolerance_m

        kept << index
        queue << [a, index] << [index, b]
      end
    end

    def farthest_from_chord(coordinates, a, b)
      # Flat-earth metres around the chord's start: plenty accurate at day scale.
      lat0 = coordinates[a][1] * Math::PI / 180
      to_xy = ->(c) { [(c[0] - coordinates[a][0]) * 111_320 * Math.cos(lat0), (c[1] - coordinates[a][1]) * 110_540] }
      bx, by = to_xy.call(coordinates[b])
      len = Math.hypot(bx, by)
      ((a + 1)...b).map do |i|
        x, y = to_xy.call(coordinates[i])
        d = len.zero? ? Math.hypot(x, y) : ((x * by) - (y * bx)).abs / len
        [i, d]
      end.max_by(&:last)
    end

    def build_point(xml, coord, route_start, zone)
      lon, lat, ele, m = coord
      time = route_start + m.to_f

      xml.trkpt(lat: lat, lon: lon) do
        xml.ele(ele.round(1)) if ele
        xml.time(localize(time, zone))
      end
    end

    # Builds a { waypoint_id => <wpt> fragment } hash for the named,
    # non-pass-through waypoints on this route, using the same arrival
    # coordinate (and thus elevation + time) computed for the track.
    def build_waypoint_xmls(waypoints, arrivals, coordinates, route_start, zone)
      waypoints.each_with_object({}) do |wp, xmls|
        next if wp.routing?

        idx = arrivals[wp.id]
        coord = idx && coordinates[idx]
        next unless coord

        lon, lat, ele, m = coord
        time = route_start + m.to_f

        wxml = Builder::XmlMarkup.new(indent: 2)
        wxml.wpt(lat: lat, lon: lon) do
          wxml.ele(ele.round(1)) if ele
          wxml.time(localize(time, zone))
          wxml.name(wp.name) if wp.name.present?
        end
        xmls[wp.id] = wxml.target!
      end
    end

    # Re-anchors a naive Time's Y/M/D H:M:S digits to the given
    # ActiveSupport::TimeZone, so the digits (already the intended local
    # wall-clock values) are serialized with the correct real-world UTC
    # offset rather than a misleading 'Z'.
    def localize(naive_time, zone)
      return naive_time.iso8601 unless zone

      zone.local(
        naive_time.year, naive_time.month, naive_time.day,
        naive_time.hour, naive_time.min, naive_time.sec
      ).iso8601
    end

    # Looks up (and caches) the ActiveSupport::TimeZone for a route from
    # the Boundary containing its starting coordinate — same pattern as
    # TelemetryLog.current_timezone.
    def route_timezone(route)
      @route_timezones ||= {}
      @route_timezones.fetch(route.id) do
        coord     = route.geom&.coordinates&.first
        zone_name = coord && Boundary.containing_point(coord[1], coord[0])
                                     .where.not(timezone: nil)
                                     .order(level: :desc)
                                     .pluck(:timezone)
                                     .first
        @route_timezones[route.id] = zone_name && Time.find_zone(zone_name)
      end
    end

    # Maps coordinate index → stop delay (seconds) at that point.
    #
    # Mirrors Routing::DurationImporter's exact segment/waypoint pairing
    # (waypoints[i] pairs with segments[i], the leg *departing* that
    # waypoint) so inserted hold-points line up with how M was actually
    # stamped when the route was calculated.
    def stop_delays_by_index(waypoints, segments)
      delays = {}

      (segments || []).each_with_index do |segment, i|
        delay = waypoints[i]&.delay.to_f
        next unless delay.positive?

        first_idx = segment['steps']&.first&.dig('way_points', 0)
        delays[first_idx] = delay if first_idx
      end

      delays
    end

    # Maps waypoint id → the coordinate index at which that waypoint is
    # *arrived at* (i.e. the last point of the segment leading into it).
    # The first waypoint departs at index 0 (no incoming segment).
    def waypoint_arrivals(waypoints, segments)
      arrivals = {}
      arrivals[waypoints.first.id] = 0 if waypoints.first

      (segments || []).each_with_index do |segment, i|
        next_wp = waypoints[i + 1]
        next unless next_wp

        last_idx = segment['steps']&.last&.dig('way_points', -1)
        arrivals[next_wp.id] = last_idx if last_idx
      end

      arrivals
    end

    def track_name(route_sequence)
      label = route_sequence.route_name.presence || "Day #{route_sequence.day}"
      date  = route_sequence.date
      date ? "#{date.iso8601} – #{label}" : label
    end

    def trip_start
      @trip_start ||= @trip.start_on.to_time(:utc)
    end

    # Wraps a set of days into one GPX document: deduped <wpt> elements
    # first (a day's arrival waypoint is often the next day's departure
    # waypoint), then one <trk> per day, per GPX 1.1 element ordering.
    def wrap_days(days)
      seen_wpts = {}
      days.each { |day| day[:wpt_xmls].each { |id, xml| seen_wpts[id] ||= xml } }

      xml = Builder::XmlMarkup.new(indent: 2)
      xml.instruct!
      xml.gpx(
        xmlns: 'http://www.topografix.com/GPX/1/1',
        'xmlns:xsi' => 'http://www.w3.org/2001/XMLSchema-instance',
        'xsi:schemaLocation' => 'http://www.topografix.com/GPX/1/1 ' \
                                 'http://www.topografix.com/GPX/1/1/gpx.xsd',
        version: '1.1',
        creator: 'trip-planner'
      ) do
        xml.metadata { xml.name(@trip.name) }
        seen_wpts.each_value { |w| xml << w }
        days.each { |day| xml << day[:track_xml] }
      end
      xml.target!
    end
  end
end
