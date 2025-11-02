# frozen_string_literal: true

module DashboardHelper
  def heading_to_direction(heading)
    HeadingCalculator.heading_to_direction(heading)
  end
end
