# frozen_string_literal: true

module Landing
  # Longitude/latitude to the hero map's 320x400 SVG coordinates. This is the
  # projection the outline data in config/landing/south_america_outlines.json was
  # drawn with (equirectangular, longitude scaled by cos(-22 degrees)), so routes
  # line up with the country shapes. Points checked against the design:
  # Sao Paulo -> (217.2, 211.1), Ushuaia -> (108.2, 380.8).
  module MapProjection
    LON0 = -82.5
    LON1 = -33.5
    LAT0 = -56.5
    LAT1 = 13.5
    WIDTH = 320
    HEIGHT = 400
    PADDING = 10
    K = Math.cos(-22 * Math::PI / 180)

    SX = (LON1 - LON0) * K
    SY = LAT1 - LAT0
    SCALE = [(WIDTH - (2 * PADDING)) / SX, (HEIGHT - (2 * PADDING)) / SY].min
    OX = (WIDTH - (SX * SCALE)) / 2
    OY = (HEIGHT - (SY * SCALE)) / 2

    module_function

    # @return [Array(Float, Float)] x, y rounded to a tenth of a pixel
    def project(lon, lat)
      [(OX + ((lon - LON0) * K * SCALE)).round(1), (OY + ((LAT1 - lat) * SCALE)).round(1)]
    end
  end
end
