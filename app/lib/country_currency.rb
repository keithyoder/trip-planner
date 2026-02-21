# frozen_string_literal: true

# Maps South American country names (as symbols) to their ISO 4217 currency codes.
#
# Extracted from Waypoint to give both Waypoint and GasPrice a single source of
# truth, avoiding the awkward Waypoint::COUNTRY_CURRENCY cross-model reference.
#
# Countries are keyed by the name string used in the boundaries table (level 2),
# so lookups from Waypoint#country work without any transformation beyond #to_sym.
#
# == Usage
#
#   CountryCurrency.for(:Brasil)       # => :brl
#   CountryCurrency.for(:Argentina)    # => :ars
#   CountryCurrency.for(:Unknown)      # => nil
#   CountryCurrency.fetch(:Bolivia)    # => :bob
#   CountryCurrency.fetch(:Unknown)    # => raises KeyError
#   CountryCurrency.countries          # => [:Brasil, :Uruguay, ...]
#
module CountryCurrency
  MAPPING = {
    Brasil: :brl,
    Uruguay: :uyu,
    Argentina: :ars,
    Chile: :clp,
    Bolivia: :bob,
    Perú: :pen
  }.freeze

  # Returns the currency code for a country, or nil if not found.
  #
  # @param country [Symbol, String]
  # @return [Symbol, nil]
  def self.for(country)
    MAPPING[country.to_sym]
  end

  # Returns the currency code for a country, raising KeyError if not found.
  # Mirrors Hash#fetch semantics for callers that consider a missing country
  # a programming error rather than an expected condition.
  #
  # @param country [Symbol, String]
  # @return [Symbol]
  # @raise [KeyError]
  def self.fetch(country)
    MAPPING.fetch(country.to_sym)
  end

  # Returns all supported country symbols.
  #
  # @return [Array<Symbol>]
  def self.countries
    MAPPING.keys
  end
end
