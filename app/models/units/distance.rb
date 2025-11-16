# frozen_string_literal: true

module Units
  class Distance < Unit
    UNITS = {
      meters: 'm',
      km: 'km',
      miles: 'mi',
      feet: 'ft'
    }.freeze

    CONVERSIONS = {
      meters: 1,
      km: 0.001,
      miles: 0.000621371,
      feet: 3.28084
    }.freeze

    class << self
      def base_unit
        :meters
      end
    end

    # Define convenience methods for each unit
    UNITS.each_key do |unit_name|
      define_method unit_name do
        to_units(unit_name)
      end
    end

    # ActiveRecord Type specific to Distance
    class Type < Unit::Type
      def initialize(opts = {})
        opts[:class] = Distance
        super(opts)
      end
    end
  end
end

# Backward compatibility: expose Distance at top level
Distance = Units::Distance
