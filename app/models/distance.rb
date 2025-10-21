# frozen_string_literal: true

require 'forwardable'

class Distance
  extend Forwardable

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

  attr_reader :value, :units

  def_delegators :value, :to_i, :to_f, :to_d

  def self.convert(value, units, new_units)
    return value if new_units == units
    return value * CONVERSIONS[new_units] if units == :meters

    value * CONVERSIONS[new_units] / CONVERSIONS[units]
  end

  def initialize(value, units: :meters)
    if value.is_a? Distance
      units = value.units
      value = value.to_d
    end
    @value = value.to_d
    @units = units
    # super(@value)
  end

  def inspect
    to_s(units: true)
  end

  def to_s(units: false, decimals: 2)
    num = decimals.zero? ? value.round.to_i.to_i : value.round(decimals).to_s
    return num unless units

    "#{num} #{UNITS[self.units]}"
  end

  def round(decimals = 0)
    Distance.new(value.round(decimals), units: units)
  end

  def to_units(new_units)
    return self if units == new_units

    Distance.new(Distance.convert(value, units, new_units), units: new_units)
  end

  UNITS.each_key do |new_units|
    define_method new_units do
      to_units(new_units)
    end
  end

  def *(other)
    Distance.new(value * other, units: units)
  end

  def /(other)
    Distance.new(value / other, units: units)
  end

  def +(other)
    return Distance.new(meters.value + other.meters.value, units: :meters).send(units) if other.is_a? Distance

    Distance.new(value + other, units: units)
  end

  def -(other)
    return Distance.new(meters.value - other.meters.value, units: :meters).send(units) if other.is_a? Distance

    Distance.new(value - other, units: units)
  end

  def abs
    Distance.new(value.abs, units: units)
  end

  class Type < ActiveRecord::Type::Value
    attr_reader :units

    def initialize(opts = {})
      @units = opts.delete(:units) || :meters
    end

    def cast(value)
      return nil if value.nil?
      return value if value.is_a? Distance

      Distance.new(value, units: units)
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
