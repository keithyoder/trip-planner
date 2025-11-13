# frozen_string_literal: true

require 'forwardable'

class Speed # rubocop:disable Style/Documentation
  extend Forwardable

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

  attr_reader :value, :units

  def_delegators :value, :to_i, :to_f, :to_d

  def self.convert(value, units, new_units)
    return value if new_units == units
    return value * CONVERSIONS[new_units] if units == :meters_per_second

    value * CONVERSIONS[new_units] / CONVERSIONS[units]
  end

  def initialize(value, units: :meters_per_second)
    if value.is_a? Speed
      units = value.units
      value = value.to_d
    end
    @value = value.to_d
    @units = units
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
    Speed.new(value.round(decimals), units: units)
  end

  def to_units(new_units)
    return self if units == new_units

    Speed.new(Speed.convert(value, units, new_units), units: new_units)
  end

  def default
    to_units(DEFAULT_SPEED)
  end

  UNITS.each_key do |new_units|
    define_method new_units do
      to_units(new_units)
    end
  end

  def *(other)
    unless other.is_a?(ActiveSupport::Duration) || other.is_a?(Numeric)
      raise ArgumentError, 'Can only multiply Speed by Duration or Numeric'
    end

    # Speed * Time = Distance
    # Convert speed to m/s, duration to seconds, multiply to get meters
    time_in_seconds = other.is_a?(ActiveSupport::Duration) ? other.to_f : other
    distance_in_meters = meters_per_second.value * time_in_seconds
    Distance.new(distance_in_meters, units: :meters)
  end

  def /(other)
    if other.is_a?(Distance)
      # Speed / Distance = Time (Duration)
      # Convert both to base units: m/s and meters
      time_in_seconds = other.meters.value / meters_per_second.value
      time_in_seconds.seconds # Returns ActiveSupport::Duration
    elsif other.is_a?(Numeric)
      # Scalar division
      Speed.new(value / other, units: units)
    else
      raise ArgumentError, 'Can only divide Speed by Distance or Numeric'
    end
  end

  def <=>(other)
    return nil unless other.is_a?(Speed)

    meters_per_second.value <=> other.meters_per_second.value
  end

  include Comparable

  def abs
    Speed.new(value.abs, units: units)
  end

  class Type < ActiveRecord::Type::Value # rubocop:disable Style/Documentation
    attr_reader :units

    def initialize(opts = {})
      super()
      @units = opts.delete(:units) || :meters_per_second
    end

    def cast(value)
      return nil if value.nil?
      return value if value.is_a? Speed

      Speed.new(value, units: units)
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
