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

    puts waypoint.waypoint_type
    if waypoint.waypoint_type == 'gas_station'
      "#{waypoint.toll} liters"
    else
      money = Money.from_amount(waypoint.toll, waypoint.currency)

      "#{money.format} (#{money.exchange_to(:brl).format})"
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
        toll_formatted: waypoint.toll ? number_to_currency(waypoint.toll, unit: 'R$ ') : nil
        # segment_distance: waypoint.segment_distance ? "#{waypoint.segment_distance.km.round(1)} km" : nil,
        # trip_distance: waypoint.trip_distance ? "#{number_with_delimiter(waypoint.trip_distance.km.round.to_i)} km" : nil
      }
    end.to_json
  end

  # Get Bootstrap icon class for waypoint type
  # @param waypoint_type [String, Symbol] The waypoint type
  # @return [String] Bootstrap icon class name
  def waypoint_icon_class(waypoint_type)
    icons = {
      'overnight' => 'bi-moon-stars-fill',
      'lunch' => 'bi-cup-hot-fill',
      'ferry_boarding' => 'bi-water',
      'ferry_disembarkment' => 'bi-water',
      'toll_booth' => 'bi-cash-coin',
      'border_crossing' => 'bi-shield-check',
      'gas_station' => 'bi-fuel-pump-fill',
      'attraction' => 'bi-camera-fill',
      'routing' => 'bi-signpost-2-fill'
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
      'routing' => '#6c757d'
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
      'routing' => '#e9ecef'
    }

    bg_colors[waypoint_type.to_s] || bg_colors['routing']
  end
end
