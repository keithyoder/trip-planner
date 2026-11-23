# frozen_string_literal: true

# Formatting and SVG geometry for the read-only /follow pages. The charts are
# plain server-rendered SVG, so they need no JavaScript and show on first paint.
module FollowHelper
  CHART_LEFT = 16.0
  CHART_WIDTH = 288.0

  # Distances, heights and temperatures follow the locale (units.* in the locale
  # files), like the rest of the app. The services hand over metres and Celsius.
  def follow_distance(meters)
    follow_measure(meters, t('units.distance'), t('units.distance_abbr'))
  end

  def follow_elevation(meters, abbr: true)
    follow_measure(meters, t('units.elevation'), abbr ? t('units.elevation_abbr') : nil)
  end

  def follow_temp(celsius, degree_only: false)
    value = Units::Temperature.new(celsius, units: :celsius).to_units(t('units.temperature')).value.to_f.round
    degree_only ? "#{value}°" : "#{value} #{t('units.temperature_abbr')}"
  end

  # Seconds from midnight -> "08:30".
  # Road surface in the visitor's language; the key is the ORS type name, so a
  # type nobody has translated yet still reads sensibly instead of raising.
  def follow_surface(surface_type)
    key = surface_type.to_s
    t("surface_types.#{key}", default: key.tr('_', ' ').capitalize)
  end

  def follow_clock(seconds)
    format('%<h>02d:%<m>02d', h: (seconds / 3600).floor % 24, m: ((seconds % 3600) / 60).round % 60)
  end

  def follow_time(time)
    time.strftime('%H:%M')
  end

  def follow_duration(minutes)
    hours, mins = minutes.divmod(60)
    return t('follow.min_only', m: mins) if hours.zero?

    t('follow.hours_min', h: hours, m: format('%02d', mins))
  end

  # x position on the 0-24 h charts (viewBox 320 wide, 16 px margins).
  def follow_hour_x(hours)
    (CHART_LEFT + CHART_WIDTH * hours / 24.0).round(1)
  end

  def follow_seconds_x(seconds)
    follow_hour_x(seconds / 3600.0)
  end

  def follow_time_x(time)
    follow_hour_x(time.hour + time.min / 60.0)
  end

  # Altitude profile as an area + line in a 640x140 box.
  def follow_elevation_paths(profile)
    return {} if profile.size < 2

    km_max = profile.last.first.to_f
    alts = profile.map(&:last)
    low, high = alts.minmax
    span = [high - low, 1].max
    points = profile.map do |km, alt|
      [(10 + 620 * km / [km_max, 0.01].max).round(1), (120 - 100.0 * (alt - low) / span).round(1)]
    end
    line = points.map { |x, y| "#{x},#{y}" }.join(' ')
    { line: line, area: "10,125 #{line} 630,125", low: low, high: high }
  end

  # Hourly temperature curve in a 320x150 box (y from the day's own min/max).
  def follow_curve(hourly)
    return {} if hourly.blank?

    low, high = hourly.values.minmax
    span = [high - low, 1].max
    y = ->(temp) { (118 - 90.0 * (temp - low) / span).round(1) }
    # Gridlines at the day's low, middle and high, so the curve can be read as numbers.
    grid = [low, (low + high) / 2.0, high].map { |temp| { y: y.call(temp), label: follow_temp(temp) } }
    { line: hourly.map { |h, temp| "#{follow_hour_x(h)},#{y.call(temp)}" }.join(' '), y: y, grid: grid }
  end

  private

  def follow_measure(meters, unit, abbr)
    value = Units::Distance.new(meters.to_f).to_units(unit).value.to_f.round
    text = number_with_delimiter(value, delimiter: t('number.format.delimiter'))
    abbr ? "#{text} #{abbr}" : text
  end
end
