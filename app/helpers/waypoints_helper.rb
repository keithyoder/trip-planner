module WaypointsHelper
  def humanize(secs)
    # Convert seconds to a human-readable format
    # Round to the nearest minute
    secs = (secs / 60).round * 60
    [[60, :seconds], [60, :minutes], [24, :hours], [Float::INFINITY, :days]].map{ |count, name|
      if secs > 0
        secs, n = secs.divmod(count)

        "#{n.to_i} #{name}" unless n.to_i==0
      end
    }.compact.reverse.join(' ')
  end

  def format_currency(waypoint)
    return unless waypoint.toll.present?
    
    puts waypoint.waypoint_type
    if waypoint.waypoint_type == "gas_station"
      "#{waypoint.toll} liters"
    else
      money = Money.from_amount(waypoint.toll, waypoint.currency)

      "#{money.format} (#{money.exchange_to(:brl).format})"
    end
  end
end
