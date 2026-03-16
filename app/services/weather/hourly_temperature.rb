# frozen_string_literal: true

# app/services/weather/hourly_temperature.rb
#
# Models the diurnal temperature curve for a location on a given date using
# the sine-exponential method anchored to real solar geometry.
#
# The curve has three phases:
#
#   1. Pre-sunrise  — exponential decay from the previous day's peak toward min
#   2. Rising       — sine curve from min (at sunrise) to max (at peak hour)
#   3. Falling      — exponential decay from max onward
#
# Peak temperature lags behind solar noon by a fraction of the noon-to-sunset
# window (PEAK_LAG_FRACTION). This is physically motivated: the surface
# continues absorbing more energy than it radiates well into the afternoon.
# Using actual solar geometry from SolarPosition makes the curve location- and
# season-aware rather than relying on a fixed offset.
#
# Not waypoint-specific — takes any Weather::Result and SolarPosition.
#
# == Usage
#
#   solar  = SolarPosition.new(date, coordinates, timezone)
#   result = Weather::Historical.new(lat:, lon:, date:).fetch
#   curve  = Weather::HourlyTemperature.new(result, solar)
#
#   curve.at(14)            # => 22.4  (°C at 14:00 local time)
#   curve.at(14, unit: :f)  # => 72.3  (°F)
#   curve.all               # => { 0 => 8.1, 1 => 7.4, ..., 23 => 10.2 }
#   curve.peak_hour         # => 15.67 (fractional hour of peak temperature)
#
module Weather
  class HourlyTemperature
    # Fraction of the solar-noon-to-sunset window after which peak temperature
    # occurs. 0.35 ≈ 35% of the way from noon to sunset.
    # For a 4.5h noon-to-sunset window, peak falls ~1.6h after noon.
    PEAK_LAG_FRACTION = 0.35

    # Exponential decay rate per hour for the falling and pre-sunrise phases.
    # Lower = slower overnight cooling; higher = faster post-peak drop.
    DECAY_RATE = 0.1

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
    # Exposed for display (e.g. "peak around 15:30").
    #
    # @return [Float]
    def peak_hour
      @peak_hour ||= solar_noon_hour + (sunset_hour - solar_noon_hour) * PEAK_LAG_FRACTION
    end

    private

    def calculate(hour)
      t_min = @result.temp_min&.celsius&.value&.to_f
      t_max = @result.temp_max&.celsius&.value&.to_f
      return nil unless t_min && t_max

      temp = if hour < sunrise_hour
               # Phase 1: Pre-sunrise — exponential decay from previous peak toward min.
               # We treat today's max as the prior-day peak (climate normals give the
               # same shape day-to-day). Hours are extended by 24 to cross midnight.
               hours_since_peak = (hour + 24) - peak_hour
               t_max * Math.exp(-DECAY_RATE * hours_since_peak)

             elsif hour <= peak_hour
               # Phase 2: Rising — sine from min at sunrise to max at peak.
               rise_window = peak_hour - sunrise_hour
               progress    = rise_window.positive? ? (hour - sunrise_hour) / rise_window : 1.0
               t_min + (t_max - t_min) * Math.sin(Math::PI / 2 * progress)

             else
               # Phase 3: Falling — exponential decay from max at peak onward.
               hours_past_peak = hour - peak_hour
               t_max * Math.exp(-DECAY_RATE * hours_past_peak)
             end

      temp.clamp(t_min, t_max).round(1)
    end

    # Convert a TimeWithZone to a fractional hour (e.g. 06:45 → 6.75)
    def to_fractional_hour(time)
      time.hour + time.min / 60.0 + time.sec / 3600.0
    end

    def sunrise_hour
      @sunrise_hour ||= to_fractional_hour(@solar.sunrise)
    end

    def solar_noon_hour
      @solar_noon_hour ||= to_fractional_hour(@solar.solar_noon)
    end

    def sunset_hour
      @sunset_hour ||= to_fractional_hour(@solar.sunset)
    end
  end
end
