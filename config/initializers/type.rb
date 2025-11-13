# frozen_string_literal: true

ActiveRecord::Type.register(:distance) { |_type, **args| Distance::Type.new(args) }
ActiveRecord::Type.register(:speed) { |_type, **args| Speed::Type.new(args) }

DEFAULT_DISTANCE = :miles
DEFAULT_SPEED = :miles_per_hour
