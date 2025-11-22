# frozen_string_literal: true

module Units
  class FuelConsumption < Unit
    UNITS = {
      liters_per_100km: 'L/100km',
      mpg_us: 'MPG',
      mpg_uk: 'MPG (UK)',
      km_per_liter: 'km/L'
    }.freeze

    # Conversion formulas to/from base unit (liters_per_100km)
    # Note: MPG and km/L are inverse relationships
    CONVERSIONS = {
      liters_per_100km: ->(value) { value },
      mpg_us: ->(value) { 235.214 / value },
      mpg_uk: ->(value) { 282.481 / value },
      km_per_liter: ->(value) { 100.0 / value }
    }.freeze

    # Inverse conversions (from unit to base)
    INVERSE_CONVERSIONS = {
      liters_per_100km: ->(value) { value },
      mpg_us: ->(value) { 235.214 / value },
      mpg_uk: ->(value) { 282.481 / value },
      km_per_liter: ->(value) { 100.0 / value }
    }.freeze

    class << self
      def base_unit
        :liters_per_100km
      end

      def convert(value, from_units, to_units)
        validate_unit!(from_units)
        validate_unit!(to_units)

        return value if to_units == from_units

        # Convert to base unit first
        base_value = if from_units == base_unit
                       value
                     else
                       CONVERSIONS[from_units].call(value)
                     end

        # Convert from base to target
        CONVERSIONS[to_units].call(base_value)
      end
    end

    # Define convenience methods for each unit
    UNITS.each_key do |unit_name|
      define_method unit_name do
        to_units(unit_name)
      end
    end

    # ActiveRecord Type specific to FuelConsumption
    class Type < Unit::Type
      def initialize(opts = {})
        opts[:class] = FuelConsumption
        super(opts)
      end
    end

    # Locale-aware default unit
    def self.default_unit_for_locale(locale)
      case locale.to_s
      when 'en'
        :mpg_us
      else # es, pt
        :liters_per_100km
      end
    end
  end
end
