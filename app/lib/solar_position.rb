# frozen_string_literal: true

# Calculates solar event times (dawn, sunrise, solar noon, sunset, dusk) for a
# given date, coordinates, and timezone using the NOAA solar calculation algorithm.
#
# This is a pure Ruby value object with no database or framework dependencies.
# Instantiate it with a date, a coordinate object responding to #latitude and
# #longitude, and an optional IANA timezone string.
#
# @example
#   position = SolarPosition.new(Date.today, waypoint.lonlat, waypoint.timezone)
#   position.sunrise   # => ActiveSupport::TimeWithZone
#   position.day_length  # => ActiveSupport::Duration
#
# References:
#   https://gml.noaa.gov/grad/solcalc/solareqns.PDF
#
class SolarPosition
  # The sun's zenith angle at sunrise/sunset (includes atmospheric refraction)
  RISE_SET_ANGLE = 90.833 # degrees

  # The sun's zenith angle at civil twilight
  CIVIL_TWILIGHT_ANGLE = 96.0 # degrees

  DEFAULT_TIMEZONE = 'America/Recife'

  # @param date [Date, DateTime] the date to calculate for
  # @param coordinates [Object] responds to #latitude and #longitude (degrees)
  # @param timezone [String] IANA timezone string (default: 'America/Recife')
  def initialize(date, coordinates, timezone = DEFAULT_TIMEZONE)
    @date = date.to_datetime
    @coordinates = coordinates
    @offset = @date.in_time_zone(timezone).utc_offset
  end

  # @return [ActiveSupport::TimeWithZone] start of civil twilight in the morning
  def dawn
    @dawn ||= to_datetime(720 - 4 * (@coordinates.longitude + degrees(hora_angle(CIVIL_TWILIGHT_ANGLE))) - eqtime)
  end

  # @return [ActiveSupport::TimeWithZone]
  def sunrise
    @sunrise ||= to_datetime(720 - 4 * (@coordinates.longitude + degrees(hora_angle(RISE_SET_ANGLE))) - eqtime)
  end

  # @return [ActiveSupport::TimeWithZone]
  def solar_noon
    @solar_noon ||= to_datetime(720 - 4 * @coordinates.longitude - eqtime)
  end

  # @return [ActiveSupport::TimeWithZone]
  def sunset
    @sunset ||= to_datetime(720 - 4 * (@coordinates.longitude + degrees(-1 * hora_angle(RISE_SET_ANGLE))) - eqtime)
  end

  # @return [ActiveSupport::TimeWithZone] end of civil twilight in the evening
  def dusk
    @dusk ||= to_datetime(720 - 4 * (@coordinates.longitude + degrees(-1 * hora_angle(CIVIL_TWILIGHT_ANGLE))) - eqtime)
  end

  # @return [ActiveSupport::Duration] elapsed time between sunrise and sunset
  def day_length
    @day_length ||= ActiveSupport::Duration.build(sunset.to_i - sunrise.to_i)
  end

  private

  # Fractional year in radians, used as the input to all Fourier series below.
  def fractional_year
    @fractional_year ||= 2 * Math::PI * (@date.yday - 1 + (@date.hour - 12) / 24.0) / 365.0
  end

  # Equation of time in minutes — accounts for the eccentricity of Earth's orbit
  # and the obliquity of the ecliptic.
  def eqtime # rubocop:disable Metrics/AbcSize
    @eqtime ||= 229.18 * (
      0.000075 +
      0.001868 * Math.cos(fractional_year) -
      0.032077 * Math.sin(fractional_year) -
      0.014615 * Math.cos(2 * fractional_year) -
      0.040849 * Math.sin(2 * fractional_year)
    )
  end

  # Solar declination in radians — the angle between the sun and the equatorial
  # plane, which varies through the year as Earth orbits the sun.
  def declination # rubocop:disable Metrics/AbcSize
    @declination ||=
      0.006918 -
      0.399912 * Math.cos(fractional_year) +
      0.070257 * Math.sin(fractional_year) -
      0.006758 * Math.cos(2 * fractional_year) +
      0.000907 * Math.sin(2 * fractional_year) -
      0.002697 * Math.cos(3 * fractional_year) +
      0.001480 * Math.sin(3 * fractional_year)
  end

  # Converts degrees to radians.
  def radians(degrees)
    degrees * Math::PI / 180
  end

  # Converts radians to degrees.
  def degrees(radians)
    radians * 180 / Math::PI
  end

  # Converts a number of minutes-from-midnight into a datetime anchored to
  # the calculation date, adjusted for the local UTC offset.
  #
  # @param minutes [Numeric] minutes from solar midnight
  # @return [ActiveSupport::TimeWithZone]
  def to_datetime(minutes)
    @date.beginning_of_day + minutes.minutes + @offset.seconds
  end

  # Calculates the hour angle for a given zenith angle using the standard
  # NOAA formula. Returns the angle in radians.
  #
  # @param zenith_angle [Float] degrees
  # @return [Float] radians
  def hora_angle(zenith_angle)
    Math.acos(
      (Math.cos(radians(zenith_angle)) /
        (Math.cos(radians(@coordinates.latitude)) * Math.cos(declination))) -
      (Math.tan(radians(@coordinates.latitude)) * Math.tan(declination))
    )
  end
end
