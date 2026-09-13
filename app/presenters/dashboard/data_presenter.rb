# frozen_string_literal: true

require 'heading_calculator'

module Dashboard
  # Formats a single TelemetryLog + trip-detection state into the JSON
  # payload the dashboard's live map/widgets consume -- used by both
  # DashboardController's JSON action and TelemetrySyncService's
  # ActionCable broadcasts, so both stay in sync automatically instead of
  # drifting the way DashboardController's old private methods did.
  class DataPresenter
    include LocalizedUnits
    include HeadingCalculator

    # @param log [TelemetryLog]
    # @param trip_detector [TripDetector, nil]
    # @param today_distance [Units::Distance, Numeric] total distance so far today
    # @param locale [Symbol, String]
    def initialize(log, trip_detector: nil, today_distance: 0, locale: I18n.locale)
      @log = log
      @trip_detector = trip_detector
      @today_distance = today_distance.is_a?(Units::Distance) ? today_distance : Units::Distance.new(today_distance)
      @locale = locale
    end

    # @return [Hash, nil] nil when there's no log to build from
    def as_json(*)
      return nil unless log

      {
        travelling: travelling?,
        distance: distance,
        speed: speed_data,
        elevation: elevation_data,
        gps: gps_data,
        device: log.data['device'],
        transport_mode: log.data['ios_activity'],
        weather: weather_data,
        timestamp: log.timestamp.iso8601
      }
    end

    private

    attr_reader :log, :trip_detector, :today_distance, :locale

    def travelling?
      trip_detector&.currently_travelling? || false
    end

    # Locale-appropriate unit (miles for en, km for es/pt), as a plain
    # number -- the odometer widget renders this digit-by-digit, so it
    # needs a raw Float, not a Units object or a "X km" string.
    def distance
      localized(today_distance, 1).value.to_f
    end

    def speed_data
      gps_speed = log.data['gps_speed']
      return { value: 0.0, unit: Units::Speed::UNITS[locale_speed_unit] } unless gps_speed

      mps = gps_speed.to_f
      converted = localized(Units::Speed.new(mps), 1)
      { value: converted.value.to_f, unit: Units::Speed::UNITS[locale_speed_unit] }
    end

    def locale_speed_unit
      @locale_speed_unit ||= I18n.t('units.speed', locale: locale).to_sym
    end

    def elevation_data
      meters = log.data['barometric_altitude']
      return nil if meters.nil?

      unit = I18n.t('units.elevation', locale: locale).to_sym
      converted = Units::Distance.new(meters).to_units(unit).round(0)
      { value: converted.value.to_f, unit: Units::Distance::UNITS[unit] }
    end

    def gps_data
      altitude = localized_altitude(log.data['gps_altitude']&.to_f)

      {
        lat: log.data['gps_latitude']&.to_f,
        lon: log.data['gps_longitude']&.to_f,
        altitude: altitude&.value&.to_f,
        altitude_unit: altitude && Units::Distance::UNITS[altitude.units],
        heading: log.data['gps_heading']&.to_f,
        direction: heading_to_direction(log.data['gps_heading']&.to_f),
        climb: log.data['gps_climb']&.to_f,
        satellites: log.data['gps_satellites']&.to_i
      }
    end

    def localized_altitude(meters)
      return nil if meters.nil?

      unit = I18n.t('units.elevation', locale: locale).to_sym
      Units::Distance.new(meters).to_units(unit).round(0)
    end

    def weather_data
      temp = localized_temperature(log.data['shtc3_temperature'])
      dew = localized_temperature(log.data['shtc3_dewpoint'])

      {
        temperature: temp&.value&.to_f,
        temperature_unit: temp && Units::Temperature::UNITS[temp.units],
        humidity: log.data['shtc3_humidity']&.round(1),
        pressure: log.data['bmp581_pressure']&.round(1),
        dewpoint: dew&.value&.to_f,
        dewpoint_unit: dew && Units::Temperature::UNITS[dew.units]
      }
    end

    def localized_temperature(celsius_value)
      return nil if celsius_value.nil?

      localized(Units::Temperature.new(celsius_value, units: :celsius), 1)
    end
  end
end
