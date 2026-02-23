# frozen_string_literal: true

# app/models/budget.rb
#
# Budget
#
# A value object that aggregates all costs for a trip into a structured budget.
# All costs derive from the `toll` column on each waypoint, but the column
# stores different things depending on waypoint_type:
#
#   gas_station      -> litres of fuel consumed (toll × local gas price = cost)
#   toll_booth       -> road toll amount in local currency
#   overnight        -> lodging cost in local currency
#   lunch            -> meal cost in local currency
#   ferry_boarding   -> ferry fare in local currency
#   attraction       -> entrance fee in local currency
#   parking          -> parking fee in local currency
#
# All amounts are converted to a single target currency for summary totals,
# while line items retain their original currency for display.
# Labels and translations are handled in the view layer.
#
class Budget
  # A single budget line item.
  # `amount` is in the waypoint's local currency.
  # The view is responsible for translation and formatting.
  BudgetItem = Data.define(
    :waypoint,   # Waypoint — the source waypoint
    :category,   # Symbol — one of the CATEGORY_MAP values or :other
    :amount,     # Money — in the waypoint's original local currency
    :country     # String — country name for context
  )

  # Maps waypoint_type -> budget category.
  # nil means the type carries no cost and is excluded from the budget.
  CATEGORY_MAP = {
    overnight:            :lodging,
    lunch:                :meals,
    toll_booth:           :tolls,
    ferry_boarding:       :ferry,
    ferry_disembarkment:  nil,
    attraction:           :attractions,
    parking:              :parking,
    gas_station:          :fuel,
    border_crossing:      nil,
    routing:              nil,
    bank:                 nil
  }.freeze

  attr_reader :trip, :currency

  # @param trip [Trip] The trip to budget
  # @param currency [Symbol] Target currency for totals (e.g. :brl, :usd)
  def initialize(trip, currency: :brl)
    @trip = trip
    @currency = currency
  end

  # All budget line items, ordered by waypoint sequence
  #
  # @return [Array<BudgetItem>]
  def line_items
    @line_items ||= build_line_items
  end

  # Total trip cost in target currency
  #
  # @return [Money]
  def total
    @total ||= line_items
      .map { |item| item.amount.exchange_to(currency) }
      .sum(Money.new(0, currency))
  end

  # Totals grouped by category, in target currency
  #
  # @return [Hash<Symbol, Money>]
  def by_category
    @by_category ||= line_items
      .group_by(&:category)
      .transform_values do |items|
        items
          .map { |item| item.amount.exchange_to(currency) }
          .sum(Money.new(0, currency))
      end
  end

  # Line items for a specific category
  #
  # @param category [Symbol]
  # @return [Array<BudgetItem>]
  def items_for(category)
    line_items.select { |item| item.category == category }
  end

  # Convenience accessors for common categories

  def fuel_cost
    by_category.fetch(:fuel, Money.new(0, currency))
  end

  def lodging_cost
    by_category.fetch(:lodging, Money.new(0, currency))
  end

  def meals_cost
    by_category.fetch(:meals, Money.new(0, currency))
  end

  def tolls_cost
    by_category.fetch(:tolls, Money.new(0, currency))
  end

  def ferry_cost
    by_category.fetch(:ferry, Money.new(0, currency))
  end

  def attractions_cost
    by_category.fetch(:attractions, Money.new(0, currency))
  end

  def parking_cost
    by_category.fetch(:parking, Money.new(0, currency))
  end

  # Percentage of total budget per category
  #
  # @return [Hash<Symbol, Float>]
  def category_percentages
    total_fractional = total.fractional.to_f
    return {} if total_fractional.zero?

    by_category.transform_values do |amount|
      (amount.exchange_to(currency).fractional.to_f / total_fractional * 100).round(1)
    end
  end

  private

  def build_line_items
    costed_waypoints.filter_map do |waypoint|
      category = CATEGORY_MAP[waypoint.waypoint_type&.to_sym]

      # Skip types explicitly mapped to nil (no budget cost)
      next if CATEGORY_MAP.key?(waypoint.waypoint_type&.to_sym) && category.nil?

      category ||= :other

      amount = if waypoint.gas_station?
                 fuel_cost_for(waypoint)
               else
                 monetary_cost_for(waypoint)
               end

      next if amount.nil?

      BudgetItem.new(
        waypoint: waypoint,
        category: category,
        amount: amount,
        country: country_for(waypoint) || 'Unknown'
      )
    end
  end

  # Resolve country name from already-preloaded boundaries (level 2) in memory,
  # avoiding the N+1 pluck that waypoint.country would otherwise trigger.
  #
  # @param waypoint [Waypoint]
  # @return [String, nil]
  def country_for(waypoint)
    waypoint.boundaries.find { |b| b.level == 2 }&.name
  end

  # For gas_station waypoints: toll holds litres, multiply by local price per litre
  #
  # @param waypoint [Waypoint]
  # @return [Money, nil]
  def fuel_cost_for(waypoint)
    country_sym = country_for(waypoint)&.to_sym
    return nil unless country_sym && GasPrice.countries.include?(country_sym)

    litres = waypoint.toll.to_d
    price_per_litre = GasPrice.in_local_currency(country_sym)

    volume = Units::Volume.new(litres, units: :liters)
    volume * price_per_litre
  end

  # For all other waypoint types: toll holds the monetary amount in local currency
  #
  # @param waypoint [Waypoint]
  # @return [Money]
  def monetary_cost_for(waypoint)
    country_sym = country_for(waypoint)&.to_sym
    wp_currency = (country_sym && CountryCurrency.for(country_sym)) || currency
    Money.new(toll_in_minor_units(waypoint.toll, wp_currency), wp_currency)
  end

  # Converts a decimal toll amount to integer minor units for the Money gem.
  # e.g. 52.50 BRL -> 5250 centavos
  #
  # @param amount [Decimal]
  # @param currency_code [Symbol, String]
  # @return [Integer]
  def toll_in_minor_units(amount, currency_code)
    subunit_to_unit = Money::Currency.new(currency_code).subunit_to_unit
    (amount.to_d * subunit_to_unit).round.to_i
  end

  # Waypoints with a non-zero toll value, in trip sequence order.
  # Boundaries are preloaded without geometry columns to avoid loading
  # expensive multipolygon data — we only need name, level, and hierarchy.
  def costed_waypoints
    @costed_waypoints ||= trip.waypoints
                              .where.not(toll: [nil, 0])
                              .order(:sequence)
                              .tap do |waypoints|
                                ActiveRecord::Associations::Preloader.new(
                                  records: waypoints,
                                  associations: :boundaries,
                                  scope: Boundary.without_geom
                                ).call
                              end
  end
end