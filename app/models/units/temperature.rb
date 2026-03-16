# frozen_string_literal: true

module Units
  # Temperature unit with non-linear conversion (offset + scale).
  #
  # Unlike Distance or Speed, temperature conversions between Celsius and
  # Fahrenheit require an additive offset, not just a multiplier. The base
  # class convert method (multiplicative only) is overridden here.
  #
  # Base unit is Celsius — all internal storage is in °C.
  #
  # @example
  #   t = Units::Temperature.new(20, units: :celsius)
  #   t.fahrenheit        # => Units::Temperature (68.0 °F)
  #   t.fahrenheit.value  # => 68.0
  #   t.to_units(:fahrenheit).value # => 68.0
  #
  class Temperature < Unit
    UNITS = {
      celsius: '°C',
      fahrenheit: '°F'
    }.freeze

    # CONVERSIONS is not used for temperature — convert is overridden below.
    # Defined to satisfy the base class constant requirement.
    CONVERSIONS = {
      celsius: 1,
      fahrenheit: 1
    }.freeze

    class << self
      def base_unit
        :celsius
      end

      # The preferred temperature unit for the current I18n locale.
      # Reads from units.temperature in the locale file.
      def locale_unit
        I18n.t('units.temperature').to_sym
      end

      # The abbreviated string for the current locale's temperature unit.
      def locale_abbr
        I18n.t('units.temperature_abbr')
      end

      # Override multiplicative convert with offset-aware temperature conversion.
      def convert(value, from_units, to_units)
        validate_unit!(from_units)
        validate_unit!(to_units)
        return value if from_units == to_units

        celsius = case from_units
                  when :celsius    then value
                  when :fahrenheit then (value - 32) * 5.0 / 9.0
                  end

        case to_units
        when :celsius    then celsius
        when :fahrenheit then (celsius * 9.0 / 5.0) + 32
        end
      end
    end

    # Convenience methods
    def celsius
      to_units(:celsius)
    end

    def fahrenheit
      to_units(:fahrenheit)
    end

    # Convert to the current locale's preferred unit
    def locale
      to_units(self.class.locale_unit)
    end

    # ActiveRecord Type specific to Temperature
    class Type < Unit::Type
      def initialize(opts = {})
        opts[:class] = Temperature
        super(opts)
      end
    end
  end
end

# Backward compatibility: expose at top level
Temperature = Units::Temperature
