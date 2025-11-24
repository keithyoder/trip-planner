# frozen_string_literal: true

require 'forwardable'

module Units
  class InvalidUnitError < StandardError; end

  # Base class for unit-based measurements (Distance, Speed, Temperature, etc.)
  #
  # This abstract class provides a framework for creating type-safe measurement classes
  # with automatic unit conversion, validation, and mathematical operations.
  #
  # @abstract Subclasses must define UNITS, CONVERSIONS constants and base_unit class method
  #
  # @example Creating a Distance subclass
  #   class Distance < Units::Unit
  #     UNITS = {
  #       meters: 'm',
  #       km: 'km',
  #       miles: 'mi'
  #     }.freeze
  #
  #     CONVERSIONS = {
  #       meters: 1,
  #       km: 0.001,
  #       miles: 0.000621371
  #     }.freeze
  #
  #     def self.base_unit
  #       :meters
  #     end
  #   end
  #
  # Required Subclass Implementation:
  # - UNITS constant: Hash mapping unit symbols to abbreviation strings
  # - CONVERSIONS constant: Hash mapping unit symbols to conversion multipliers
  # - base_unit class method: Returns the base unit symbol (used for arithmetic)
  #
  # Optional Subclass Customization:
  # - Override arithmetic operators (*, /) for special behavior (e.g., Speed * Time = Distance)
  # - Define convenience methods for each unit (e.g., def km; to_units(:km); end)
  # - Override convert method for non-linear conversions (e.g., temperature)
  #
  # @attr_reader [BigDecimal] value The numeric value of the measurement
  # @attr_reader [Symbol] units The unit symbol for this measurement
  class Unit
    extend Forwardable

    attr_reader :value, :units

    def_delegators :value, :to_i, :to_f, :to_d

    class << self
      def convert(value, from_units, to_units)
        validate_unit!(from_units)
        validate_unit!(to_units)

        return value if to_units == from_units
        return value * self::CONVERSIONS[to_units] if from_units == base_unit

        value * self::CONVERSIONS[to_units] / self::CONVERSIONS[from_units]
      end

      def validate_unit!(unit)
        return if self::UNITS.key?(unit) || self::UNITS.key?(unit.to_sym)

        valid_units = self::UNITS.keys.join(', ')
        raise InvalidUnitError, "Invalid unit: #{unit.inspect}. Valid units are: #{valid_units}"
      end

      def base_unit
        # Override in subclasses to specify the base unit
        # e.g., :meters for Distance, :meters_per_second for Speed
        raise NotImplementedError, 'Subclasses must define base_unit'
      end
    end

    def initialize(value, units: nil)
      units ||= self.class.base_unit

      # Handle initialization from same type
      if value.is_a?(self.class)
        units = value.units
        value = value.to_d
      end

      # Validate units on initialization
      self.class.validate_unit!(units)

      @value = value.to_d
      @units = units
    end

    def inspect
      to_s(units: true)
    end

    def to_s(units: false, decimals: 2)
      num = decimals.zero? ? value.round.to_i : value.round(decimals).to_s
      return num unless units

      "#{num} #{self.class::UNITS[self.units]}"
    end

    def round(decimals = 0)
      self.class.new(value.round(decimals), units: units)
    end

    def to_units(new_units)
      new_units = new_units.to_sym
      # Validate units on conversion
      self.class.validate_unit!(new_units)

      return self if units == new_units

      self.class.new(self.class.convert(value, units, new_units), units: new_units)
    end

    # Alias to match the helper's expectation
    alias to_unit to_units

    def zero?
      value.zero?
    end

    def abs
      self.class.new(value.abs, units: units)
    end

    def coerce(other)
      raise TypeError, "#{self.class} can't be coerced into #{other.class}" unless other.is_a?(Numeric)

      [self.class.new(other, units: @units), self]
    end

    def as_json(_options = {})
      to_f # or to_d, or to_kilometers, depending on what you want
    end

    # Arithmetic operations for same-type objects
    def +(other) # rubocop:disable Metrics/AbcSize
      if other.is_a?(self.class)
        base = self.class.base_unit
        result_value = send(base).value + other.send(base).value
        self.class.new(result_value, units: base).send(units)
      else
        self.class.new(value + other, units: units)
      end
    end

    def -(other) # rubocop:disable Metrics/AbcSize
      if other.is_a?(self.class)
        base = self.class.base_unit
        result_value = send(base).value - other.send(base).value
        self.class.new(result_value, units: base).send(units)
      else
        self.class.new(value - other, units: units)
      end
    end

    # Scalar multiplication and division
    def *(other)
      self.class.new(value * other, units: units)
    end

    def /(other)
      self.class.new(value / other, units: units)
    end

    # Comparison
    def <=>(other)
      return nil unless other.is_a?(self.class)

      base = self.class.base_unit
      send(base).value <=> other.send(base).value
    end

    include Comparable

    # ActiveRecord Type for serialization
    class Type < ActiveRecord::Type::Value
      attr_reader :units, :unit_class

      def initialize(opts = {})
        super()
        @unit_class = opts.delete(:class)
        @units = opts.delete(:units) || @unit_class.base_unit
        @unit_class.validate_unit!(@units)
      end

      def cast(value)
        return nil if value.nil?
        return value if value.is_a?(@unit_class)

        @unit_class.new(value, units: units)
      end

      def serialize(value)
        return if value.nil?

        value.send(units).value.to_s
      end

      def deserialize(value)
        cast(value)
      end
    end
  end
end
