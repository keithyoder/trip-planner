# frozen_string_literal: true

module RoutesHelper
  def elevation_chart(route)
    elevations = route.elevations
    y_min = [0, elevations.map { |e| e.elevation.round(0) }.min || 0].min
    elevation_data = elevations.map do |e|
      [e.distance.to_f.round(1), e.elevation.round(0)]
    end

    line_chart(
      elevation_data,
      id: "elevation-chart",
      points: false,
      library: {
        scales: {
          x: {
            title: { display: true, text: t('units.distance_abbr') }
          },
          y: {
            min: y_min,
            title: { display: true, text: t('units.elevation_abbr') }
          }
        }
      }
    )
  end
end
