# frozen_string_literal: true

# app/services/weather/result.rb
#
# Value object returned by both Weather::Historical and Weather::Forecast.
# Temperature fields are Units::Temperature instances (base unit: celsius).
# Wind speed fields are Units::Speed instances (base unit: meters_per_second).
# Std dev fields are plain Floats — they are deltas in the same unit as their
# parent field, not independent measurements that need conversion.
#
# Views use the unit helpers they use everywhere else in the app:
#
#   result.temp_max.to_units(:fahrenheit).value  # => 81.0
#   result.temp_max.fahrenheit.value             # => 81.0
#   result.windspeed.km_per_hour.value           # => 22.0
#   result.windspeed.miles_per_hour.value        # => 13.7
#
# All user-facing strings go through I18n using keys in config/locales/*/weather.yml.
#
module Weather
  Result = Struct.new(
    :lat, :lon, :date,
    :temp_mean,                         # Units::Temperature (celsius)
    :temp_min,                          # Units::Temperature (celsius)
    :temp_max,                          # Units::Temperature (celsius)
    :temp_min_std,                      # Float — std dev in °C
    :temp_max_std,                      # Float — std dev in °C
    :precipitation_mm, :precipitation_std, :precipitation_years,
    :windspeed,                         # Units::Speed (meters_per_second)
    :windspeed_std,                     # Float — std dev in km/h
    :windspeed_max,                     # Units::Speed (meters_per_second)
    :windspeed_max_std,                 # Float — std dev in km/h
    :humidity_pct,                      # Integer 0–100
    :source,                            # :climate_normal | :forecast
    # ── Forecast-only fields (nil for climate_normal) ─────────────────────
    :weathercode,                       # Integer — WMO weather interpretation code
    :cloudcover_pct,                    # Integer 0–100 — total cloud cover
    :precipitation_hours,               # Integer — hours with precipitation in the day
    :precipitation_probability_max,     # Integer 0–100 — Open-Meteo's own probability estimate
    keyword_init: true
  ) do
    # A day is "wet" if it received at least this many mm.
    PRECIP_THRESHOLD_MM = 5.0

    # ── Temperature ──────────────────────────────────────────────────────────
    #
    # Convenience accessors matching the old _c/_f naming so existing callers
    # don't need to change. These delegate to the typed Unit objects.

    def temp_mean_c = temp_mean&.celsius&.value&.to_f
    def temp_min_c  = temp_min&.celsius&.value&.to_f
    def temp_max_c  = temp_max&.celsius&.value&.to_f
    def temp_mean_f = temp_mean&.fahrenheit&.value&.to_f
    def temp_min_f  = temp_min&.fahrenheit&.value&.to_f
    def temp_max_f  = temp_max&.fahrenheit&.value&.to_f

    # Mean ± 1σ range for the daily high as [low, high] in the given unit
    def temp_max_range(unit = :celsius)
      return nil unless temp_max && temp_max_std

      base = temp_max.celsius.value.to_f
      low  = Units::Temperature.new(base - temp_max_std, units: :celsius).to_units(unit).value.round(0).to_i
      high = Units::Temperature.new(base + temp_max_std, units: :celsius).to_units(unit).value.round(0).to_i
      [low, high]
    end

    # Mean ± 1σ range for the daily low as [low, high] in the given unit
    def temp_min_range(unit = :celsius)
      return nil unless temp_min && temp_min_std

      base = temp_min.celsius.value.to_f
      low  = Units::Temperature.new(base - temp_min_std, units: :celsius).to_units(unit).value.round(0).to_i
      high = Units::Temperature.new(base + temp_min_std, units: :celsius).to_units(unit).value.round(0).to_i
      [low, high]
    end

    # Backward-compatible aliases
    def temp_max_range_c = temp_max_range(:celsius)
    def temp_min_range_c = temp_min_range(:celsius)
    def temp_max_range_f = temp_max_range(:fahrenheit)
    def temp_min_range_f = temp_min_range(:fahrenheit)

    # ── Wind ─────────────────────────────────────────────────────────────────

    # Convenience accessors for the most common display unit
    def windspeed_kmh     = windspeed&.km_per_hour&.value&.to_f
    def windspeed_max_kmh = windspeed_max&.km_per_hour&.value&.to_f

    # Mean ± 1σ range for daily mean wind, floored at 0, in km/h
    def windspeed_range_kmh
      return nil unless windspeed && windspeed_std

      base = windspeed.km_per_hour.value.to_f
      [[0, (base - windspeed_std)].max.round(0).to_i,
       (base + windspeed_std).round(0).to_i]
    end

    # Mean ± 1σ range for daily max wind, floored at 0, in km/h
    def windspeed_max_range_kmh
      return nil unless windspeed_max && windspeed_max_std

      base = windspeed_max.km_per_hour.value.to_f
      [[0, (base - windspeed_max_std)].max.round(0).to_i,
       (base + windspeed_max_std).round(0).to_i]
    end

    # ── Precipitation ─────────────────────────────────────────────────────────

    # Mean ± 1σ for daily precipitation, floored at 0
    def precip_range_mm
      return nil unless precipitation_mm && precipitation_std

      [[0, (precipitation_mm - precipitation_std)].max.round(1),
       (precipitation_mm + precipitation_std).round(1)]
    end

    # Fraction of years where precipitation met or exceeded PRECIP_THRESHOLD_MM.
    # NOTE: patched via define_singleton_method when loaded from WeatherEstimate.
    def precip_probability
      return nil if precipitation_years.nil? || precipitation_years.empty?

      wet = precipitation_years.count { |v| v >= PRECIP_THRESHOLD_MM }
      (wet.to_f / precipitation_years.size * 100).round(0).to_i
    end

    def precip_probability_label
      p = precip_probability
      return nil if p.nil?

      key = case p
            when 0..15  then 'very_unlikely'
            when 16..35 then 'unlikely'
            when 36..55 then 'possible'
            when 56..75 then 'likely'
            when 76..90 then 'very_likely'
            else             'almost_certain'
            end
      I18n.t("weather.precip_probability.#{key}")
    end

    # ── Humidity ───────────────────────────────────────────────────────────────

    def humidity_label
      return nil unless humidity_pct

      key = case humidity_pct
            when 0..25  then 'very_dry'
            when 26..45 then 'dry'
            when 46..60 then 'comfortable'
            when 61..75 then 'humid'
            when 76..85 then 'very_humid'
            else             'oppressive'
            end
      I18n.t("weather.humidity.#{key}")
    end

    # ── Forecast-only helpers ─────────────────────────────────────────────────

    # Human-readable label for the WMO weather code.
    # Returns nil for climate_normal results (no weathercode).
    # Full WMO code table: https://open-meteo.com/en/docs#weathervariables
    def weathercode_label
      return nil unless weathercode

      key = case weathercode
            when 0      then 'clear'
            when 1      then 'mainly_clear'
            when 2      then 'partly_cloudy'
            when 3      then 'overcast'
            when 45, 48 then 'fog'
            when 51, 53 then 'light_drizzle'
            when 55     then 'heavy_drizzle'
            when 61, 63 then 'light_rain'
            when 65     then 'heavy_rain'
            when 71, 73 then 'light_snow'
            when 75     then 'heavy_snow'
            when 77     then 'snow_grains'
            when 80, 81 then 'light_showers'
            when 82     then 'heavy_showers'
            when 85, 86 then 'snow_showers'
            when 95     then 'thunderstorm'
            when 96, 99 then 'thunderstorm_hail'
            else             'unknown'
            end
      I18n.t("weather.weathercode.#{key}")
    end

    # Bootstrap icon name for the weathercode, suitable for <i class="bi bi-...">
    def weathercode_icon
      return nil unless weathercode

      case weathercode
      when 0      then 'sun'
      when 1      then 'sun'
      when 2      then 'cloud-sun'
      when 3      then 'cloud'
      when 45, 48 then 'cloud-fog'
      when 51..55 then 'cloud-drizzle'
      when 61..65 then 'cloud-rain'
      when 71..77 then 'cloud-snow'
      when 80..82 then 'cloud-rain-heavy'
      when 85, 86 then 'cloud-snow'
      when 95     then 'cloud-lightning-rain'
      when 96, 99 then 'cloud-lightning-rain'
      else             'cloud'
      end
    end

    # ── Source predicates ──────────────────────────────────────────────────────

    def forecast?       = source == :forecast
    def climate_normal? = source == :climate_normal

    # ── Summary ───────────────────────────────────────────────────────────────

    def description
      [temp_text, precip_text, wind_text, humidity_text, conditions_text].compact.join(' · ')
    end

    def to_h
      super.merge(
        temp_max_range_c: temp_max_range_c,
        temp_min_range_c: temp_min_range_c,
        windspeed_range_kmh: windspeed_range_kmh,
        windspeed_max_range_kmh: windspeed_max_range_kmh,
        precip_probability: precip_probability,
        precip_range_mm: precip_range_mm,
        humidity_label: humidity_label,
        weathercode_label: weathercode_label,
        weathercode_icon: weathercode_icon,
        description: description
      )
    end

    private

    def temp_text
      return nil unless temp_max && temp_min

      high_range = temp_max_range_c ? " (#{temp_max_range_c[0]}–#{temp_max_range_c[1]}°C)" : ''
      low_range  = temp_min_range_c ? " (#{temp_min_range_c[0]}–#{temp_min_range_c[1]}°C)" : ''

      I18n.t('weather.temp_summary',
             high: temp_max.celsius.value.round(0).to_i,
             high_range: high_range,
             low: temp_min.celsius.value.round(0).to_i,
             low_range: low_range)
    end

    def precip_text
      prob  = precip_probability
      label = precip_probability_label
      return I18n.t('weather.rain_very_unlikely') if prob&.<=(15)
      return nil if prob.nil?

      avg_text = precipitation_mm&.positive? ? I18n.t('weather.avg_mm', mm: precipitation_mm.round(1)) : ''
      I18n.t('weather.rain_summary', label: label, prob: prob, avg: avg_text)
    end

    def wind_text
      return nil unless windspeed

      kmh        = windspeed.km_per_hour.value.to_f
      label      = wind_label(kmh)
      mean_range = windspeed_range_kmh
      max_range  = windspeed_max_range_kmh

      parts = [I18n.t('weather.wind_mean', label: label, speed: kmh.round(0))]
      parts << I18n.t('weather.wind_mean_range', low: mean_range[0], high: mean_range[1]) if mean_range

      if windspeed_max
        max_kmh = windspeed_max.km_per_hour.value.to_f
        parts << I18n.t('weather.wind_max', speed: max_kmh.round(0))
        parts << I18n.t('weather.wind_max_range', low: max_range[0], high: max_range[1]) if max_range
      end

      parts.join(' ')
    end

    def wind_label(kmh)
      key = case kmh
            when 0...10  then 'calm'
            when 10...20 then 'light'
            when 20...35 then 'moderate'
            when 35...50 then 'strong'
            else              'very_strong'
            end
      I18n.t("weather.wind_label.#{key}")
    end

    def humidity_text
      return nil unless humidity_pct

      I18n.t('weather.humidity_summary', pct: humidity_pct, label: humidity_label)
    end

    def conditions_text
      return nil unless weathercode_label

      parts = [weathercode_label]
      parts << I18n.t('weather.cloudcover', pct: cloudcover_pct) if cloudcover_pct
      parts << I18n.t('weather.precip_hours', hours: precipitation_hours) if precipitation_hours&.positive?
      parts.join(', ')
    end
  end
end
