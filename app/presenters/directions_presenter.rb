# frozen_string_literal: true

# app/presenters/directions_presenter.rb
#
# Each row represents a waypoint. The collapsible below it shows the steps
# for the leg DEPARTING from that waypoint (how you get to the next one).
# When the next leg is transit, "no turn-by-turn" is shown instead.
#
class DirectionsPresenter
  MIN_STEP_DISTANCE = 5

  Row = Data.define(
    :waypoint,        # Waypoint
    :index,           # Integer
    :first,           # Boolean — true for the first displayed row
    :arrival_time,    # String or nil — when you arrived here
    :transit,         # Boolean — this waypoint is a transit stop
    :arriving_profile, # String or nil — profile of the leg that arrived here
    :segment,         # Hash or nil — outgoing ORS segment
    :steps,           # Array<Step> — walking steps departing here
    :segment_class    # String — Bootstrap table class
  ) do
    def transit? = transit
    def first?   = first
  end

  Step = Data.define(
    :instruction,
    :distance,
    :speed,
    :time,
    :lat,
    :lon
  )

  def initialize(route)
    @route = route
  end

  def has_geometry?
    @route.geom.present?
  end

  def coordinates
    @coordinates ||= @route.geom.coordinates
  end

  def rows
    @rows ||= build_rows
  end

  private

  def build_rows
    all_waypoints = @route.waypoints.to_a
    segments      = @route.segments || []

    # departing_seg_for[sequence] → segment index (steps shown under departure)
    # arriving_seg_for[sequence]  → segment index (arrival time shown here)
    #
    # Every consecutive non-routing pair produces one segment — ORS for
    # driving/walking legs, GoogleMaps for transit legs.
    departing_seg_for = {}
    arriving_seg_for  = {}
    seg_idx = 0

    all_waypoints.each_cons(2) do |a, b|
      next if a.routing? || b.routing?

      departing_seg_for[a.sequence] = seg_idx
      arriving_seg_for[b.sequence]  = seg_idx
      seg_idx += 1
    end

    first_row = true

    all_waypoints.each_with_index.filter_map do |waypoint, idx|
      next if waypoint.routing?

      is_first = first_row
      first_row = false

      next_wp = all_waypoints[(idx + 1)..].find { |wp| !wp.routing? }
      prev_wp = all_waypoints[0...idx].reverse.find { |wp| !wp.routing? }

      incoming_idx     = arriving_seg_for[waypoint.sequence]
      incoming_segment = incoming_idx ? segments[incoming_idx] : nil

      outgoing_idx     = departing_seg_for[waypoint.sequence]
      outgoing_segment = outgoing_idx ? segments[outgoing_idx] : nil

      # arriving_profile drives the badge shown on this row.
      # - nil if this is the first waypoint (no leg arrived here)
      # - waypoint.profile if a segment arrived here (walking/driving/transit)

      Row.new(
        waypoint: waypoint,
        index: idx,
        first: is_first,
        arrival_time: build_arrival_time(incoming_segment, waypoint),
        transit: waypoint.transit?,
        arriving_profile: prev_wp.nil? ? nil : waypoint.profile,
        segment: outgoing_segment,
        steps: outgoing_segment ? build_steps(outgoing_segment) : [],
        segment_class: segment_class_for(next_wp)
      )
    end
  end

  def build_arrival_time(segment, waypoint)
    return nil unless @route.start_time && segment

    last_wp_idx = segment['steps'].last&.dig('way_points', -1)
    return nil unless last_wp_idx && coordinates[last_wp_idx]&.[](3)

    base      = Time.at(@route.start_time % 86_400.0).utc
    arrival   = base + coordinates[last_wp_idx][3]
    departure = arrival + waypoint.delay.to_i

    if waypoint.delay.to_i.positive?
      "#{I18n.l(arrival, format: :time)} – #{I18n.l(departure, format: :time)}"
    else
      I18n.l(arrival, format: :time)
    end
  end

  def build_steps(segment)
    segment['steps']
      .select { |step| step['distance'].to_f > MIN_STEP_DISTANCE || step['distance'].to_f.zero? }
      .map do |step|
        coord    = coordinates[step['way_points'].first]
        distance = step['distance'].to_f
        duration = step['duration'].to_f
        Step.new(
          instruction: step['instruction'],
          distance: distance > 0 ? Units::Distance.new(distance) : nil,
          speed: distance > 0 && duration > 0 ? Units::Speed.new(distance / duration) : nil,
          time: step_time(step),
          lat: coord[1],
          lon: coord[0]
        )
      end
  end

  def step_time(step)
    return nil unless @route.start_time

    elapsed = coordinates[step['way_points'].last]&.[](3)
    return nil unless elapsed

    (Time.at(@route.start_time % 86_400.0).utc + elapsed).strftime('%H:%M')
  end

  def segment_class_for(next_waypoint)
    return 'table-info'    if next_waypoint&.ferry_disembarkment?
    return 'table-warning' if next_waypoint&.profile&.start_with?('foot-')
    return 'table-primary' if next_waypoint&.transit?

    ''
  end
end
