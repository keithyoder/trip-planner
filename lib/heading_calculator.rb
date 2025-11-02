# frozen_string_literal: true

module HeadingCalculator
  extend ActiveSupport::Concern

  # Class method that can be called directly
  def self.heading_to_direction(heading)
    return nil if heading.nil?

    directions = %w[N NE E SE S SW W NW]
    direction_index = ((heading + 22.5) / 45).floor % 8
    directions[direction_index]
  end

  # For when included in a class
  module ClassMethods
    def heading_to_direction(heading)
      HeadingCalculator.heading_to_direction(heading)
    end
  end

  # Instance method for when included
  def heading_to_direction(heading)
    HeadingCalculator.heading_to_direction(heading)
  end
end
