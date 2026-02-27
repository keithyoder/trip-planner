# frozen_string_literal: true

module RoutesHelper
  def elevation_chart(route)
    elevation_data = route.elevations.map do |e|
      [e.distance.to_f.round(1), e.elevation.round(0)]
    end

    line_chart(
      elevation_data,
      points: false,
      library: {
        scales: {
          x: {
            title: { display: true, text: t('units.distance_abbr') }
          },
          y: {
            title: { display: true, text: t('units.elevation_abbr') }
          }
        }
      }
    )
  end
end
