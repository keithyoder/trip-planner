# frozen_string_literal: true

# app/presenters/hourly_temperature_presenter.rb
#
# Prepares all data needed to render the hourly temperature chart partial.
# Encapsulates curve construction, std dev band generation, solar event
# formatting, and unit conversion — keeping the view logic-free.
#
# == Usage
#
#   presenter = HourlyTemperaturePresenter.new(waypoint)
#   presenter.renderable?        # => true if curve data is available
#   presenter.main_temps         # => [16.8, 16.1, ..., 17.7]  (24 values, locale unit)
#   presenter.warm_temps         # => [...] or nil
#   presenter.cold_temps         # => [...] or nil
#   presenter.has_std_band?      # => true for climate normals with std dev
#   presenter.temp_abbr          # => "°F" or "°C"
#   presenter.sunrise_hour       # => 7.35  (fractional, for chart x-axis)
#   presenter.sunset_hour        # => 17.88
#   presenter.peak_hour          # => 13.97
#
class HourlyTemperaturePresenter
  def initialize(waypoint)
    @waypoint = waypoint
  end

  def renderable?
    curve.present? && main_temps.any?
  end

  # ── Temperature data ────────────────────────────────────────────────────────

  # 24 hourly temperatures for the main (expected) curve, in locale unit.
  # @return [Array<Float, nil>]
  def main_temps
    @main_temps ||= hours.map { |h| curve.at(h, unit: unit_sym)&.round(1) }
  end

  # 24 hourly temperatures for the warm bound (mean + 1σ), or nil.
  # @return [Array<Float, nil>, nil]
  def warm_temps
    return nil unless has_std_band?

    @warm_temps ||= hours.map { |h| warm_curve.at(h, unit: unit_sym)&.round(1) }
  end

  # 24 hourly temperatures for the cold bound (mean - 1σ), or nil.
  # @return [Array<Float, nil>, nil]
  def cold_temps
    return nil unless has_std_band?

    @cold_temps ||= hours.map { |h| cold_curve.at(h, unit: unit_sym)&.round(1) }
  end

  # Whether the ±1σ band should be shown.
  # Only available for climate normals that have std dev data.
  def has_std_band?
    @has_std_band ||= weather&.climate_normal? &&
                      weather.temp_min_std.present? &&
                      weather.temp_max_std.present?
  end

  # ── Units ───────────────────────────────────────────────────────────────────

  def temp_unit
    @temp_unit ||= Units::Temperature.locale_unit
  end

  def temp_abbr
    @temp_abbr ||= Units::Temperature.locale_abbr
  end

  # ── Chart axis bounds ───────────────────────────────────────────────────────

  def y_min
    @y_min ||= begin
      all = [main_temps, cold_temps].compact.flatten.compact
      (all.min.to_f - padding).round
    end
  end

  def y_max
    @y_max ||= begin
      all = [main_temps, warm_temps].compact.flatten.compact
      (all.max.to_f + padding).round
    end
  end

  # ── Solar event labels (for display) ────────────────────────────────────────

  def dawn_label
    solar.dawn.strftime('%H:%M')
  end

  def solar_noon_label
    solar.solar_noon.strftime('%H:%M')
  end

  def sunrise_label
    solar.sunrise.strftime('%H:%M')
  end

  def sunset_label
    solar.sunset.strftime('%H:%M')
  end

  def dusk_label
    solar.dusk.strftime('%H:%M')
  end

  # ── Fractional hours for chart vertical line annotations ────────────────────
  # Returns a Float like 7.35 for 07:21, giving sub-hour x-axis precision.

  def sunrise_hour
    fractional_hour(solar.sunrise)
  end

  def sunset_hour
    fractional_hour(solar.sunset)
  end

  def peak_hour
    curve.peak_hour
  end

  # ── Peak label ──────────────────────────────────────────────────────────────

  def peak_label
    temp = curve.at(curve.peak_hour.floor, unit: unit_sym)&.round(1)
    peak_time = format('%02d:%02d', curve.peak_hour.floor, ((curve.peak_hour % 1) * 60).round)
    "#{temp}#{temp_abbr} ~#{peak_time}"
  end

  # ── Chart ID (unique per waypoint for pages with multiple charts) ────────────

  def chart_id
    "hourly-temp-chart-#{@waypoint.id}"
  end

  private

  HOURS = (0..23).to_a.freeze

  def hours
    HOURS
  end

  def unit_sym
    temp_unit == :fahrenheit ? :f : :c
  end

  def padding
    all = [main_temps, warm_temps, cold_temps].compact.flatten.compact
    return 2.0 if all.empty?

    ((all.max - all.min) * 0.1).round(1)
  end

  # Convert a TimeWithZone to a fractional hour (e.g. 07:21 → 7.35)
  def fractional_hour(time)
    time.hour + time.min / 60.0 + time.sec / 3600.0
  end

  def weather
    @weather ||= @waypoint.weather
  end

  def curve
    @curve ||= @waypoint.hourly_temperature_curve
  end

  def solar
    @solar ||= @waypoint.solar_position(@waypoint.planned_date)
  end

  # Warm bound curve — mean + 1σ on both min and max
  def warm_curve
    @warm_curve ||= Weather::HourlyTemperature.new(bound_result(:warm), solar)
  end

  # Cold bound curve — mean - 1σ on both min and max
  def cold_curve
    @cold_curve ||= Weather::HourlyTemperature.new(bound_result(:cold), solar)
  end

  def bound_result(direction)
    factor = direction == :warm ? 1 : -1

    Weather::Result.new(
      temp_min: Units::Temperature.new(
        weather.temp_min_c + (factor * weather.temp_min_std),
        units: :celsius
      ),
      temp_max: Units::Temperature.new(
        weather.temp_max_c + (factor * weather.temp_max_std),
        units: :celsius
      ),
      source: :climate_normal
    )
  end
end
