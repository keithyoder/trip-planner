# frozen_string_literal: true

ActiveRecord::Type.register(:distance) { |_type, **args| Units::Distance::Type.new(args) }
ActiveRecord::Type.register(:speed) { |_type, **args| Units::Speed::Type.new(args) }
ActiveRecord::Type.register(:fuel_consumption) { |_type, **args| Units::FuelConsumption::Type.new(args) }
