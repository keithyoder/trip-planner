# frozen_string_literal: true

module Units
  class Speed < Unit
    UNITS = {
      meters_per_second: 'm/s',
      km_per_hour: 'km/h',
      miles_per_hour: 'mph',
      knots: 'kn'
    }.freeze

    CONVERSIONS = {
      meters_per_second: 1,
      km_per_hour: 3.6,
      miles_per_hour: 2.23694,
      knots: 1.94384
    }.freeze

    class << self
      def base_unit
        :meters_per_second
      end
    end

    # Define convenience methods for each unit
    UNITS.each_key do |unit_name|
      define_method unit_name do
        to_units(unit_name)
      end
    end

    # Override multiplication to handle Speed * Time = Distance
    def *(other)
      unless other.is_a?(ActiveSupport::Duration) || other.is_a?(Numeric)
        raise ArgumentError, 'Can only multiply Speed by Duration or Numeric'
      end

      if other.is_a?(ActiveSupport::Duration)
        # Speed * Time = Distance
        # Convert speed to m/s, duration to seconds, multiply to get meters
        time_in_seconds = other.to_f
        distance_in_meters = meters_per_second.value * time_in_seconds
        Distance.new(distance_in_meters, units: :meters)
      else
        # Scalar multiplication
        super
      end
    end

    # Override division to handle Speed / Distance = Time
    def /(other)
      if other.is_a?(Distance)
        # Speed / Distance = Time (Duration)
        # Convert both to base units: m/s and meters
        time_in_seconds = other.meters.value / meters_per_second.value
        time_in_seconds.seconds # Returns ActiveSupport::Duration
      elsif other.is_a?(Numeric)
        # Scalar division
        super
      else
        raise ArgumentError, 'Can only divide Speed by Distance or Numeric'
      end
    end

    # In Units::Speed
    def self.locale_unit
      I18n.t('units.speed').to_sym
    end

    def self.locale_abbr
      I18n.t('units.speed_abbr')
    end

    def locale
      to_units(self.class.locale_unit)
    end

    # ActiveRecord Type specific to Speed
    class Type < Unit::Type
      def initialize(opts = {})
        opts[:class] = Speed
        super(opts)
      end
    end
  end
end

# Backward compatibility: expose Speed at top level
Speed = Units::Speed
