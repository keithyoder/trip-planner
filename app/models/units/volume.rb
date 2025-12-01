# frozen_string_literal: true

module Units
  class Volume < Unit
    UNITS = {
      liters: 'L',
      milliliters: 'mL',
      gallons_us: 'gal (US)',
      gallons_uk: 'gal (UK)',
      cubic_meters: 'm³',
      cubic_centimeters: 'cm³'
    }.freeze

    CONVERSIONS = {
      liters: 1,
      milliliters: 1000,
      gallons_us: 0.264172,
      gallons_uk: 0.219969,
      cubic_meters: 0.001,
      cubic_centimeters: 1000
    }.freeze

    class << self
      def base_unit
        :liters
      end
    end

    # Define convenience methods for each unit
    UNITS.each_key do |unit_name|
      define_method unit_name do
        to_units(unit_name)
      end
    end

    # Override division to handle Volume / Distance = FuelConsumption
    def /(other)
      if other.is_a?(Distance)
        # Volume / Distance = FuelConsumption (L/100km)
        # Convert both to base units: liters and kilometers
        liters_value = liters.value
        km_value = other.kilometers.value

        # Calculate L/100km
        liters_per_100km = (liters_value / km_value) * 100
        FuelConsumption.new(liters_per_100km, units: :liters_per_100km)
      elsif other.is_a?(Numeric)
        # Scalar division
        super
      else
        raise ArgumentError, 'Can only divide Volume by Distance or Numeric'
      end
    end

    # Override multiplication to handle Volume * Money = Money
    # Useful for: liters * price_per_liter = total_cost
    def *(other)
      if other.is_a?(Money)
        # Volume * Price per liter = Total cost
        other * liters.value
      elsif other.is_a?(Numeric)
        # Scalar multiplication
        super
      else
        raise ArgumentError, 'Can only multiply Volume by Money or Numeric'
      end
    end

    # ActiveRecord Type specific to Volume
    class Type < Unit::Type
      def initialize(opts = {})
        opts[:class] = Volume
        super(opts)
      end
    end

    # Locale-aware default unit
    def self.default_unit_for_locale(locale)
      case locale.to_s
      when 'en'
        :gallons_us
      else # es, pt
        :liters
      end
    end
  end
end
