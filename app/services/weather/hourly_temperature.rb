# frozen_string_literal: true

# app/services/weather/hourly_temperature.rb
#
# Models the diurnal temperature curve for a location on a given date using
# the sine-exponential method anchored to real solar geometry.
#
# The curve has three phases:
#
#   1. Pre-dawn     — exponential decay from t_dusk toward t_min, timed to
#                     arrive at t_min by dawn
#   2. Dawn → dusk  — sine curve rising from t_min at dawn to t_max at peak,
#                     then descending symmetrically back down through dusk
#   3. Post-dusk    — exponential decay from t_dusk toward t_min
#
# Using dawn/dusk (civil twilight) rather than sunrise/sunset means the
# temperature starts rising and falling slightly before/after the sun
# crosses the horizon, which better reflects how the atmosphere actually
# responds to changing insolation.
#
# Peak temperature lags behind solar noon by PEAK_LAG_FRACTION of the
# noon-to-dusk window.
#
# Not waypoint-specific — takes any Weather::Result and SolarPosition.
#
# == Usage
#
#   solar  = SolarPosition.new(date, coordinates, timezone)
#   result = Weather::Historical.new(lat:, lon:, date:).fetch
#   curve  = Weather::HourlyTemperature.new(result, solar)
#
#   curve.at(14)             # => 22.4  (°C at 14:00 local time)
#   curve.at(14, unit: :f)   # => 72.3  (°F)
#   curve.all                # => { 0 => 8.1, 1 => 7.4, ..., 23 => 10.2 }
#   curve.peak_hour          # => 13.84 (fractional hour of peak temperature)
#   curve.t_dusk             # => 25.1  (°C at dusk — decay start point)
#
module Weather
  class HourlyTemperature
    # Fraction of the solar-noon-to-dusk window after which peak temperature
    # occurs. 0.35 ≈ 35% of the way from noon to dusk.
    PEAK_LAG_FRACTION = 0.35

    # Decay completeness by next dawn — 3.0 means ~95% of the way to t_min.
    # Higher values steepen the overnight cooling curve.
    DECAY_COMPLETENESS = 3.0

    # @param result [Weather::Result]
    # @param solar  [SolarPosition]
    def initialize(result, solar)
      @result = result
      @solar  = solar
    end

    # Temperature at a given hour (0–23).
    #
    # @param hour [Integer] 0–23
    # @param unit [Symbol]  :c (default) or :f
    # @return [Float, nil]
    def at(hour, unit: :c)
      return nil unless @result.temp_min && @result.temp_max

      celsius = calculate(hour.to_f)
      return nil if celsius.nil?

      temp = Units::Temperature.new(celsius, units: :celsius)
      unit == :f ? temp.fahrenheit.value.to_f : temp.celsius.value.to_f
    end

    # Temperatures for all 24 hours.
    #
    # @param unit [Symbol] :c (default) or :f
    # @return [Hash{Integer => Float}]
    def all(unit: :c)
      (0..23).each_with_object({}) { |h, hash| hash[h] = at(h, unit: unit) }
    end

    # Fractional hour of the predicted temperature peak.
    #
    # @return [Float]
    def peak_hour
      @peak_hour ||= solar_noon_hour + (dusk_hour - solar_noon_hour) * PEAK_LAG_FRACTION
    end

    # Temperature at dusk — the starting point for overnight exponential decay.
    # Derived from the sine curve at dusk_hour.
    #
    # @return [Float, nil]
    def t_dusk
      return nil unless (t_min = @result.temp_min&.celsius&.value&.to_f)
      return nil unless (t_max = @result.temp_max&.celsius&.value&.to_f)

      sine_temp(dusk_hour, t_min, t_max).round(1)
    end

    private

    def calculate(hour)
      t_min = @result.temp_min&.celsius&.value&.to_f
      t_max = @result.temp_max&.celsius&.value&.to_f
      return nil unless t_min && t_max

      t_at_dusk = sine_temp(dusk_hour, t_min, t_max)

      # k is computed so the decay reaches ~95% of the way from t_dusk to
      # t_min by the following dawn — self-calibrating for any location/season.
      hours_dusk_to_dawn = (dawn_hour + 24) - dusk_hour
      k = DECAY_COMPLETENESS / hours_dusk_to_dawn

      if hour < dawn_hour
        # Phase 1: Pre-dawn — exponential decay from t_dusk toward t_min,
        # anchored to dusk (crossing midnight).
        hours_since_dusk = (hour + 24) - dusk_hour
        t_min + (t_at_dusk - t_min) * Math.exp(-k * hours_since_dusk)

      elsif hour <= dusk_hour
        # Phase 2: Dawn through dusk — sine curve.
        # Rises from t_min at dawn to t_max at peak, then descends
        # symmetrically back down through dusk.
        sine_temp(hour, t_min, t_max)

      else
        # Phase 3: Post-dusk — exponential decay from t_dusk toward t_min.
        hours_since_dusk = hour - dusk_hour
        t_min + (t_at_dusk - t_min) * Math.exp(-k * hours_since_dusk)
      end.round(1)
    end

    # Sine curve value at any hour between dawn and beyond.
    # Maps dawn → 0, peak → π/2, continuing symmetrically past peak.
    # Returns values in [t_min, t_max].
    def sine_temp(hour, t_min, t_max)
      rise_window = peak_hour - dawn_hour
      progress    = rise_window.positive? ? (hour - dawn_hour) / rise_window : 1.0
      t_min + (t_max - t_min) * Math.sin(Math::PI / 2 * progress)**1.5
    end

    # Convert a TimeWithZone to a fractional hour (e.g. 06:45 → 6.75)
    def to_fractional_hour(time)
      time.hour + time.min / 60.0 + time.sec / 3600.0
    end

    def dawn_hour
      @dawn_hour ||= to_fractional_hour(@solar.dawn)
    end

    def solar_noon_hour
      @solar_noon_hour ||= to_fractional_hour(@solar.solar_noon)
    end

    def dusk_hour
      @dusk_hour ||= to_fractional_hour(@solar.dusk)
    end
  end
end
