# frozen_string_literal: true

ActiveRecord::Type.register(:distance) { |_type, **args| Distance::Type.new(args) }
