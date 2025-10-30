# frozen_string_literal: true

class Overpass
  require 'overpass_api_ruby'
  attr_reader :response

  CATEGORIES = {
    fuel: { query: "'amenity'='fuel'", distance: 100 },
    border_crossing: { query: "'barrier'='border_control'", distance: 10 },
    ferry: { query: "'amenity'='ferry_terminal'", distance: 5 },
    restaurant: { query: "'amenity'='restaurant'", distance: 250 },
    bank: { query: "'amenity'='bank'", distance: 100 },
    hotel: { query: "'tourism'='hotel'", distance: 250 },
    toll: { query: "'barrier'='toll_booth'", distance: 5 }
  }.freeze

  def initialize(route_id, node_type)
    @node_type = node_type
    @route = Route.find(route_id)
    box = RGeo::Cartesian::BoundingBox.create_from_geometry(@route.geom)
    options = {
      bbox:
        {
          s: box.min_y,
          n: box.max_y,
          w: box.min_x,
          e: box.max_x
        },
      timeout: 900,
      maxsize: 1_073_741_824
    }

    overpass = OverpassAPI::QL.new(options)
    query = "node[#{CATEGORIES[node_type][:query]}];(._;>;);out body;"
    @response = overpass.query(query)
  end

  def close_to_route
    @response[:elements].select do |e|
      Route.distance_to_point(e[:lat], e[:lon]).find(@route.id).distance < CATEGORIES[@node_type][:distance]
    end
  end

  def import # rubocop:disable Metrics/MethodLength
    close_to_route.each do |element|
      poi = OsmPoi.find_or_initialize_by(id: element[:id])
      poi.update!(
        name: element.dig(:tags, :name),
        poi_type: @node_type,
        city: element.dig(:tags, :"addr:city"),
        street: element.dig(:tags, :"addr:street"),
        district: element.dig(:tags, :"addr:suburb"),
        geom: "POINT(#{element[:lon]} #{element[:lat]})"
      )
    end
  end
end
