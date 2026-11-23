# frozen_string_literal: true

module Landing
  # The static South America shapes behind the route: the trip countries (filled)
  # and their neighbours (outline only), as SVG path data in the map's
  # coordinates (see MapProjection). Natural Earth 50m, simplified; the file is
  # loaded once per process.
  module CountryOutlines
    FILE = Rails.root.join('config/landing/south_america_outlines.json')

    module_function

    def trip_d
      data.fetch('trip').join
    end

    def other_d
      data.fetch('other').join
    end

    def data
      @data ||= JSON.parse(File.read(FILE))
    end
  end
end
