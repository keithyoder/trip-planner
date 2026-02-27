# frozen_string_literal: true

module WaypointsHelper
  def humanize(secs)
    # Convert seconds to a human-readable format
    # Round to the nearest minute
    secs = (secs / 60).round * 60
    [[60, :seconds], [60, :minutes], [24, :hours], [Float::INFINITY, :days]].map do |count, name|
      next unless secs.positive?

      secs, n = secs.divmod(count)

      "#{n.to_i} #{name}" unless n.to_i.zero?
    end.compact.reverse.join(' ')
  end

  def format_currency(waypoint)
    return unless waypoint.toll.present?

    if waypoint.waypoint_type == 'gas_station'
      "#{waypoint.toll} liters"
    else
      money = Money.from_amount(waypoint.toll, waypoint.currency)
      if waypoint.currency != Money.default_currency.id
        "#{money.format} (#{money.exchange_to(Money.default_currency).format})"
      else
        money.format
      end
    end
  end

  # Generate JSON data for waypoints to be displayed on a map
  # @param waypoints [Array<Waypoint>] Array of waypoint objects
  # @return [String] JSON string for JavaScript consumption
  def waypoints_map_data(waypoints)
    waypoints
      .reject { |waypoint| waypoint.waypoint_type == 'routing' }
      .map do |waypoint|
        {
          lat: waypoint.lonlat.y,  # PostGIS point: y = latitude
          lon: waypoint.lonlat.x,  # PostGIS point: x = longitude
          type: waypoint.waypoint_type,
          name: waypoint.name,
          sequence: waypoint.sequence,
          toll: waypoint.toll,
          toll_formatted: waypoint.toll ? format_currency(waypoint) : nil
          # segment_distance: waypoint.segment_distance ? "#{waypoint.segment_distance.km.round(1)} km" : nil,
          # trip_distance: waypoint.trip_distance ? "#{number_with_delimiter(waypoint.trip_distance.km.round.to_i)} km" : nil
        }
    end.to_json
  end

  # Get Bootstrap icon class for waypoint type
  # @param waypoint_type [String, Symbol] The waypoint type
  # @return [String] Bootstrap icon class name
  def waypoint_icon_class(waypoint_type) # rubocop:disable Metrics/MethodLength
    icons = {
      'overnight' => 'bi-moon-stars-fill',
      'lunch' => 'bi-cup-hot-fill',
      'ferry_boarding' => 'bi-water',
      'ferry_disembarkment' => 'bi-water',
      'toll_booth' => 'bi-cash-coin',
      'border_crossing' => 'bi-shield-check',
      'gas_station' => 'bi-fuel-pump-fill',
      'attraction' => 'bi-camera-fill',
      'routing' => 'bi-signpost-2-fill',
      'parking' => 'bi-car-front-fill',
      'bank' => 'bi-currency-exchange'
    }

    icons[waypoint_type.to_s] || icons['routing']
  end

  # Get color for waypoint type
  # @param waypoint_type [String, Symbol] The waypoint type
  # @return [String] Hex color code
  def waypoint_color(waypoint_type)
    colors = {
      'overnight' => '#6f42c1',
      'lunch' => '#fd7e14',
      'ferry_boarding' => '#0dcaf0',
      'ferry_disembarkment' => '#0d6efd',
      'toll_booth' => '#198754',
      'border_crossing' => '#dc3545',
      'gas_station' => '#ffc107',
      'attraction' => '#d63384',
      'routing' => '#6c757d',
      'parking' => '#6c757d',
      'bank' => '#6c757d'
    }

    colors[waypoint_type.to_s] || colors['routing']
  end

  # Get background color for waypoint type
  # @param waypoint_type [String, Symbol] The waypoint type
  # @return [String] Hex color code
  def waypoint_background_color(waypoint_type)
    bg_colors = {
      'overnight' => '#e7d9ff',
      'lunch' => '#ffe5d0',
      'ferry_boarding' => '#cff4fc',
      'ferry_disembarkment' => '#cfe2ff',
      'toll_booth' => '#d1e7dd',
      'border_crossing' => '#f8d7da',
      'gas_station' => '#fff3cd',
      'attraction' => '#f7d6e6',
      'routing' => '#e9ecef',
      'parking' => '#e9ecef',
      'bank' => '#e9ecef'
    }

    bg_colors[waypoint_type.to_s] || bg_colors['routing']
  end

  def waypoint_statistics(waypoints)
    {
      total_count: waypoints.count,
      total_distance: waypoints.last&.trip_distance&.km&.round.to_i,
      total_tolls: waypoints.sum { |w| w.toll || 0 },
      by_type: waypoints.group_by(&:waypoint_type).transform_values(&:count),
      overnight_count: waypoints.count { |w| w.waypoint_type == 'overnight' },
      toll_count: waypoints.count { |w| w.waypoint_type == 'toll_booth' },
      gas_count: waypoints.count { |w| w.waypoint_type == 'gas_station' }
    }
  end

  def waypoint_to_map_marker(waypoint)
    {
      id: waypoint.id,
      sequence: waypoint.sequence,
      name: waypoint.name,
      type: waypoint.waypoint_type,
      lat: waypoint.lonlat&.x,
      lon: waypoint.lonlat&.y,
      icon: waypoint_icon_class(waypoint.waypoint_type),
      color: waypoint_color(waypoint.waypoint_type),
      location: waypoint.location,
      toll: waypoint.toll ? format_currency(waypoint) : nil
      # segment_distance: waypoint.segment_distance ? "#{waypoint.segment_distance.km}" : nil,
      # trip_distance: waypoint.trip_distance ? "#{number_with_delimiter(waypoint.trip_distance.km.round.to_i)} km" : nil
    }
  end

  def waypoints_by_day(waypoints)
    days = []
    current_day = []
    day_number = 1

    waypoints.each do |waypoint|
      current_day << waypoint

      next unless waypoint.waypoint_type == 'overnight'

      days << {
        day: day_number,
        waypoints: current_day,
        start: current_day.first,
        end: waypoint,
        distance: waypoint.trip_distance&.km&.round.to_i
      }
      current_day = []
      day_number += 1
    end

    unless current_day.empty?
      last_waypoint = current_day.last
      days << {
        day: day_number,
        waypoints: current_day,
        start: current_day.first,
        end: last_waypoint,
        distance: last_waypoint.trip_distance&.km&.round.to_i
      }
    end

    days
  end

  def waypoint_summary_stats(waypoints)
    stats = waypoint_statistics(waypoints)

    [
      {
        icon: 'bi-geo-alt-fill',
        label: 'Total Waypoints',
        value: stats[:total_count],
        color: 'primary'
      },
      {
        icon: 'bi-signpost',
        label: 'Total Distance',
        value: "#{number_with_delimiter(stats[:total_distance])} km",
        color: 'info'
      },
      {
        icon: 'bi-moon-stars-fill',
        label: 'Overnight Stops',
        value: stats[:overnight_count],
        color: 'purple',
        custom_color: '#6f42c1'
      },
      {
        icon: 'bi-cash-coin',
        label: 'Total Tolls',
        value: number_to_currency(stats[:total_tolls], unit: 'R$', separator: ',', delimiter: '.'),
        color: 'success'
      }
    ]
  end

  # Get Bootstrap icon class with color for directions partial
  # Combines icon class with a text color based on waypoint type
  def waypoint_type_icon(waypoint_type)
    "#{waypoint_icon_class(waypoint_type)} #{waypoint_text_color_class(waypoint_type)}"
  end

  # Bootstrap text color class for waypoint type
  def waypoint_text_color_class(waypoint_type)
    classes = {
      'overnight' => 'text-primary',
      'lunch' => 'text-warning',
      'ferry_boarding' => 'text-info',
      'ferry_disembarkment' => 'text-info',
      'toll_booth' => 'text-secondary',
      'border_crossing' => 'text-danger',
      'gas_station' => 'text-warning',
      'attraction' => 'text-warning',
      'parking' => 'text-primary',
      'bank' => 'text-success'
    }
    classes[waypoint_type.to_s] || 'text-secondary'
  end

  # Bootstrap table class for a route segment based on the arriving waypoint
  def waypoint_segment_class(next_waypoint)
    return 'table-info'    if next_waypoint&.ferry_disembarkment?
    return 'table-warning' if next_waypoint&.profile&.start_with?('foot-')

    ''
  end

  # Badge HTML for ferry or hiking segments
  def waypoint_segment_badge(next_waypoint)
    if next_waypoint&.ferry_disembarkment?
      content_tag(:span, class: 'badge bg-info text-dark ms-2 fw-normal') do
        content_tag(:i, '', class: 'bi bi-water me-1') + t('routes.show.ferry')
      end
    elsif next_waypoint&.profile&.start_with?('foot-')
      content_tag(:span, class: 'badge bg-warning text-dark ms-2 fw-normal') do
        content_tag(:i, '', class: 'bi bi-person-walking me-1') + t('routes.show.hiking')
      end
    end
  end

  def waypoint_time_range(route, segment, coordinates, waypoint)
    return nil unless route.start_time && segment

    last_wp_idx = segment['steps'].last&.dig('way_points', -1)
    return nil unless last_wp_idx && coordinates[last_wp_idx]&.[](3)

    base      = Time.at(route.start_time % 86_400.0).utc
    arrival   = base + coordinates[last_wp_idx][3]
    departure = arrival + waypoint.delay.to_i

    if waypoint.delay.to_i.positive?
      "#{I18n.l(arrival, format: :time)} – #{I18n.l(departure, format: :time)}"
    else
      I18n.l(arrival, format: :time)
    end
  end
end
