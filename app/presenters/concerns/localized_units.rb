# frozen_string_literal: true

# Include in a presenter to convert Units::* values (Distance, Speed,
# Volume, FuelConsumption, Temperature, ...) to whatever unit is
# appropriate for the presenter's locale, and round for display.
#
# Every Units::* subclass now shares Units::Unit#default_unit_for_locale,
# reading units.<i18n_key> from the locale YAML -- so this concern is a
# thin, uniform wrapper rather than branching per-class.
#
# Including class must provide a `locale` method (or attr_reader) -- the
# locale to convert into, typically passed into the presenter's
# constructor and defaulting to I18n.locale there.
#
# @example
#   class SomePresenter
#     include LocalizedUnits
#
#     def initialize(distance_meters, locale: I18n.locale)
#       @distance_meters = distance_meters
#       @locale = locale
#     end
#
#     def distance
#       localized(Units::Distance.new(@distance_meters), 2)
#     end
#
#     private
#
#     attr_reader :locale
#   end
#
module LocalizedUnits
  # @param unit_value [Units::Unit] any Units::* instance
  # @param precision [Integer] decimal places to round to
  # @return [Units::Unit] same class, converted + rounded, ready for #to_s
  def localized(unit_value, precision)
    unit_value
      .to_units(unit_value.class.default_unit_for_locale(locale))
      .round(precision)
  end
end
