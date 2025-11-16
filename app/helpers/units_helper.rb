# app/helpers/units_helper.rb
module UnitsHelper
  # Format distance with proper unit conversion and number formatting
  #
  # @param distance [Distance] Distance object
  # @param decimals [Integer] Number of decimal places (default: 1)
  # @return [String] Formatted distance with unit (e.g., "1,234.5 mi" or "1.234,5 km")
  #
  # Examples:
  #   format_distance(Distance.new(5000))           # => "3.1 mi" (en) or "5,0 km" (pt-BR)
  #   format_distance(Distance.new(5000), decimals: 2) # => "3.11 mi" (en) or "5,00 km" (pt-BR)
  #   format_distance(Distance.new(1234567))        # => "767.1 mi" (en) or "1.234,6 km" (pt-BR)
  def format_distance(distance, decimals: 1)
    return "0 #{t('units.distance_abbr')}" if distance.nil?

    converted_value = distance.to_units(t('units.distance'))

    return "0 #{t('units.distance_abbr')}" if converted_value.zero?

    # Format number with locale-specific thousands separator and decimal separator
    formatted_number = number_with_precision(
      converted_value,
      precision: decimals,
      delimiter: t('number.format.delimiter'),
      separator: t('number.format.separator')
    )

    # Return formatted distance with unit abbreviation
    "#{formatted_number} #{t('units.distance_abbr')}"
  end

  # Format speed with proper unit conversion and number formatting
  #
  # @param speed [Speed] Speed object
  # @param decimals [Integer] Number of decimal places (default: 0)
  # @return [String] Formatted speed with unit (e.g., "60 mph" or "100 km/h")
  def format_speed(speed, decimals: 0)
    return "0 #{t('units.speed_abbr')}" if speed.nil?

    converted_value = speed.to_units(t('units.speed'))

    return "0 #{t('units.speed_abbr')}" if converted_value.zero?

    # Format number with locale-specific thousands separator and decimal separator
    formatted_number = number_with_precision(
      converted_value,
      precision: decimals,
      delimiter: t('number.format.delimiter'),
      separator: t('number.format.separator')
    )

    # Return formatted speed with unit abbreviation
    "#{formatted_number} #{t('units.speed_abbr')}"
  end

  # Check if using metric system
  def metric_system?
    t('units.system') == 'metric'
  end

  # Check if using imperial system
  def imperial_system?
    t('units.system') == 'imperial'
  end
end
