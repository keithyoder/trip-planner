# frozen_string_literal: true

# Provides average gasoline prices per liter for South American countries.
#
# Prices are stored in their original currency and can be converted to any
# target currency for consistent display and calculations across multi-country
# trip planning.
#
# @example Get Brazil's gas price in local currency
#   GasPrice.in_local_currency(:Brasil)
#   # => #<Money fractional:616 currency:BRL>
#
# @example Calculate cost per 100km
#   fuel_efficiency = Units::FuelConsumption.new(8.5, :liters_per_100km)
#   GasPrice.cost_per_distance(:Brasil, fuel_efficiency, distance: 100, currency: :brl)
#   # => #<Money fractional:5236 currency:BRL> (R$ 52.36)
#
class GasPrice
  # Average gasoline prices per liter by country
  # Prices are approximate averages and should be updated periodically
  GASOLINE_PRICES = {
    Brasil: Money.from_amount(6.16, :brl),
    Argentina: Money.from_amount(1561, :ars),
    Uruguay: Money.from_amount(81, :uyu),
    Chile: Money.from_amount(1190, :clp),
    Bolivia: Money.from_amount(3.77, :bob),
    Peru: Money.from_amount(4.31, :pen)
  }.freeze

  # Returns the gasoline price for a country in its local currency
  #
  # @param country [Symbol] Country symbol (e.g., :Brasil, :Argentina)
  # @return [Money] Price per liter in the country's currency
  # @raise [KeyError] if country is not found
  def self.in_local_currency(country)
    GASOLINE_PRICES.fetch(country).exchange_to(Waypoint::COUNTRY_CURRENCY[country])
  end

  # Returns the gasoline price for a country in any specified currency
  #
  # @param country [Symbol] Country symbol
  # @param currency [Symbol] Target currency code (e.g., :usd, :brl)
  # @return [Money] Price per liter in the specified currency
  # @raise [KeyError] if country is not found
  def self.for_country(country, currency)
    GASOLINE_PRICES.fetch(country).exchange_to(currency)
  end

  # Calculates the fuel volume needed for traveling a given distance
  #
  # @param fuel_efficiency [Units::FuelConsumption] Vehicle's fuel efficiency
  # @param distance [Units::Distance] Distance to travel
  # @return [Units::Volume] Volume of fuel needed
  #
  # @example Calculate fuel needed for a trip
  #   efficiency = Units::FuelConsumption.new(8.5, :liters_per_100km)
  #   distance = Units::Distance.new(250, :kilometers)
  #   GasPrice.fuel_needed(efficiency, distance)
  #   # => #<Units::Volume @value=21.25 @units=:liters>
  #
  def self.fuel_needed(fuel_efficiency, distance)
    # Convert to base units for calculation
    liters_per_100km = fuel_efficiency.liters_per_100km.value
    km = distance.km.value

    # Calculate liters needed
    liters = (km / 100.0) * liters_per_100km
    Units::Volume.new(liters, units: :liters)
  end

  # Calculates the fuel cost for traveling a given distance
  #
  # @param country [Symbol] Country where fuel is purchased
  # @param fuel_efficiency [Units::FuelConsumption] Vehicle's fuel efficiency
  # @param distance [Units::Distance, Numeric] Distance (as Distance object or km as Numeric)
  # @param currency [Symbol] Currency for the result (defaults to country's local currency)
  # @return [Money] Total fuel cost for the distance
  #
  # @example Calculate cost for 250km trip in Brazil
  #   efficiency = Units::FuelConsumption.new(9.2, :liters_per_100km)
  #   distance = Units::Distance.new(250, :kilometers)
  #   GasPrice.cost_per_distance(:Brasil, efficiency, distance)
  #   # => #<Money fractional:14168 currency:BRL> (R$ 141.68)
  #
  # @example With numeric distance (assumes kilometers)
  #   efficiency = Units::FuelConsumption.new(25, :mpg_us)
  #   GasPrice.cost_per_distance(:Argentina, efficiency, distance: 100, currency: :usd)
  #
  def self.cost_per_distance(country, fuel_efficiency, distance:, currency: nil)
    # Convert numeric distance to Distance object if needed
    distance = Units::Distance.new(distance, units: :kilometers) if distance.is_a?(Numeric)

    # Get price per liter in target currency
    currency ||= Waypoint::COUNTRY_CURRENCY[country]
    price_per_liter = for_country(country, currency)

    # Calculate fuel volume needed
    fuel_volume = fuel_needed(fuel_efficiency, distance)

    # Calculate total cost using Volume * Money operator
    fuel_volume * price_per_liter
  end

  # Returns all supported countries
  #
  # @return [Array<Symbol>] List of country symbols
  def self.countries
    GASOLINE_PRICES.keys
  end
end
