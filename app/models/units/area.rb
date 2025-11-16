# frozen_string_literal: true

module Units
  class Area < Unit
    UNITS = {
      square_meters: 'm²',
      square_km: 'km²',
      square_miles: 'mi²',
      square_feet: 'ft²',
      hectares: 'ha',
      acres: 'ac'
    }.freeze

    # Conversions from square meters (base unit)
    CONVERSIONS = {
      square_meters: 1,
      square_km: 0.000001,           # 1 m² = 0.000001 km²
      square_miles: 3.861e-7,        # 1 m² = 0.0000003861 mi²
      square_feet: 10.7639,          # 1 m² = 10.7639 ft²
      hectares: 0.0001,              # 1 m² = 0.0001 ha (10,000 m² = 1 ha)
      acres: 0.000247105             # 1 m² = 0.000247105 ac
    }.freeze

    class << self
      def base_unit
        :square_meters
      end
    end

    # Define convenience methods for each unit
    UNITS.each_key do |unit_name|
      define_method unit_name do
        to_units(unit_name)
      end
    end

    # Override division to handle Area / Distance = Distance
    def /(other)
      if other.is_a?(Distance)
        # Area ÷ Distance = Distance
        # Convert both to base units: m² and m
        # Result is in meters
        distance_in_meters = square_meters.value / other.meters.value
        Distance.new(distance_in_meters, units: :meters)
      elsif other.is_a?(Numeric)
        # Scalar division
        super
      else
        raise ArgumentError, 'Can only divide Area by Distance or Numeric'
      end
    end

    # ActiveRecord Type specific to Area
    class Type < Unit::Type
      def initialize(opts = {})
        opts[:class] = Area
        super(opts)
      end
    end
  end
end
