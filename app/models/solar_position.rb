# frozen_string_literal: true

class SolarPosition
  include ActiveModel::Model
  include ActiveModel::Attributes

  RISE_SET_ANGLE = 90.833 # degrees, the angle of the sun below the horizon at sunrise/sunset
  CIVIL_TWILIGHT_ANGLE = 96.0 # degrees, the angle of the sun below the horizon at civil twilight

  def initialize(date, coordinates, timezone = 'America/Recife')
    @date = date.to_datetime
    @coordinates = coordinates
    @offset = @date.in_time_zone(timezone).utc_offset
    puts @offset
  end

  def dawn
    @dawn ||= to_datetime((720 - 4 * (@coordinates.longitude + degrees(hora_angle(CIVIL_TWILIGHT_ANGLE))) - eqtime))
  end

  def sunrise
    @sunrise ||= to_datetime((720 - 4 * (@coordinates.longitude + degrees(hora_angle(RISE_SET_ANGLE))) - eqtime))
  end

  def solar_noon
    @solar_noon ||= to_datetime(720 - 4 * @coordinates.longitude - eqtime)
  end

  def sunset
    @sunset ||= to_datetime((720 - 4 * (@coordinates.longitude + degrees(-1 * hora_angle(RISE_SET_ANGLE))) - eqtime))
  end

  def dusk
    @dusk ||= to_datetime((720 - 4 * (@coordinates.longitude + degrees(-1 * hora_angle(CIVIL_TWILIGHT_ANGLE))) - eqtime))
  end

  def day_length
    @day_length ||= ActiveSupport::Duration.build(sunset.to_i - sunrise.to_i)
  end

  private

  def fractional_year
    @fractional_year ||= 2 * Math::PI * (@date.yday - 1 + (@date.hour - 12) / 24.0) / 365.0
  end

  def eqtime
    @eqtime ||= 229.18 * (0.000075 + 0.001868 * Math.cos(fractional_year) -
      0.032077 * Math.sin(fractional_year) -
      0.014615 * Math.cos(2 * fractional_year) -
      0.040849 * Math.sin(2 * fractional_year))
  end

  def declination
    @declination ||= 0.006918 -
                     0.399912 * Math.cos(fractional_year) +
                     0.070257 * Math.sin(fractional_year) -
                     0.006758 * Math.cos(2 * fractional_year) +
                     0.000907 * Math.sin(2 * fractional_year) -
                     0.002697 * Math.cos(3 * fractional_year) +
                     0.00148 * Math.sin(3 * fractional_year)
  end

  def radians(degrees)
    degrees * Math::PI / 180
  end

  def degrees(radians)
    radians * 180 / Math::PI
  end

  def to_datetime(minutes)
    @date.beginning_of_day + minutes.minutes + @offset.seconds
  end

  def hora_angle(angle)
    Math.acos(
      (Math.cos(radians(angle)) / (Math.cos(radians(@coordinates.latitude)) * Math.cos(declination))) -
        (Math.tan(radians(@coordinates.latitude)) * Math.tan(declination))
    )
  end
end
