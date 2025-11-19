# frozen_string_literal: true

class Overpass
  require 'overpass_api_ruby'
  attr_reader :response

  CATEGORIES = {
    fuel: { query: "'amenity'='fuel'", distance: 100, types: [:node] },
    border_crossing: { query: "'barrier'='border_control'", distance: 10, types: %i[node way] },
    ferry: { query: "'amenity'='ferry_terminal'", distance: 5, types: %i[node way] },
    restaurant: { query: "'amenity'='restaurant'", distance: 250, types: %i[node way] },
    bank: { query: "'amenity'='bank'", distance: 100, types: %i[node way] },
    hotel: { query: "'tourism'='hotel'", distance: 250, types: %i[node way] },
    toll: { query: "'barrier'='toll_booth'", distance: 5, types: %i[node way] },
    parking: { query: "'amenity'='parking'", distance: 100, types: %i[way relation] },
    park: { query: "'leisure'='park'", distance: 500, types: %i[way relation] },
    rest_area: { query: "'highway'='rest_area'", distance: 100, types: %i[node way] }
  }.freeze

  def initialize(route_id, node_type)
    @node_type = node_type
    # @route = Route.find(route_id)
    @max_distance = CATEGORIES[node_type][:distance]

    @route = Route.with_bbox.find(route_id)

    # box = RGeo::Cartesian::BoundingBox.create_from_geometry(@route.geom)
    options = {
      bbox: {
        s: @route.bbox_s,
        n: @route.bbox_n,
        w: @route.bbox_w,
        e: @route.bbox_e
      },
      timeout: 900,
      maxsize: 1_073_741_824
    }

    overpass = OverpassAPI::QL.new(options)
    query = build_query
    @response = overpass.query(query)
  rescue JSON::ParserError
    @response = overpass.query(query)
  end

  def close_to_route
    @close_to_route ||= begin
      elements_with_geom = @response[:elements].filter_map do |element|
        geom = element_to_geometry(element)
        next unless geom

        { element: element, geom: geom }
      end

      return [] if elements_with_geom.empty?

      # Batch calculate distances in a single query
      calculate_distances_batch(elements_with_geom)
    end
  end

  def import
    return if close_to_route.empty?

    close_to_route.each do |element|
      OsmPoiImporter.import_from_overpass(element, @node_type)
    end
  end

  def pois_for_map
    close_to_route.map do |poi|
      {
        osm_id: osm_id_for_element(poi),
        lat: latitude_for_element(poi),
        lon: longitude_for_element(poi),
        name: poi.dig(:tags, :name),
        street: poi.dig(:tags, :"addr:street"),
        city: poi.dig(:tags, :"addr:city"),
        toll_amount: poi.dig(:tags, :toll) || poi.dig(:tags, :charge),
        operator: poi.dig(:tags, :operator)
      }
    end
  end

  private

  def build_query
    category = CATEGORIES[@node_type]
    types = category[:types]

    # Build query for each type (node, way, relation)
    queries = types.map do |type|
      case type
      when :node
        "node[#{category[:query]}]"
      when :way
        "way[#{category[:query]}]"
      when :relation
        "relation[#{category[:query]}]"
      end
    end

    # Combine queries and request geometry data
    "(#{queries.join(';')};);out body geom;"
  end

  def element_to_geometry(element)
    case element[:type]
    when 'node'
      node_to_point(element)
    when 'way'
      way_to_geometry(element)
    when 'relation'
      relation_to_geometry(element)
    end
  rescue StandardError => e
    Rails.logger.warn "Failed to create geometry for #{element[:type]} #{element[:id]}: #{e.message}"
    nil
  end

  def node_to_point(element)
    return nil unless element[:lat] && element[:lon]

    "POINT(#{element[:lon]} #{element[:lat]})"
  end

  def way_to_geometry(element)
    return nil unless element[:geometry]&.any?

    coords = element[:geometry].map { |node| "#{node[:lon]} #{node[:lat]}" }
    return nil if coords.size < 2

    # Check if way is closed (polygon)
    first_coord = element[:geometry].first
    last_coord = element[:geometry].last

    if coords.size >= 4 && first_coord[:lat] == last_coord[:lat] && first_coord[:lon] == last_coord[:lon]
      "POLYGON((#{coords.join(', ')}))"
    else
      "LINESTRING(#{coords.join(', ')})"
    end
  end

  def relation_to_geometry(element)
    # For relations, we'll use the center point if available
    # or calculate centroid from members
    return nil unless element[:center] || element[:members]&.any?

    if element[:center]
      "POINT(#{element[:center][:lon]} #{element[:center][:lat]})"
    else
      # Try to build geometry from outer members
      build_relation_from_members(element)
    end
  end

  def build_relation_from_members(element)
    # Extract coordinates from all way members with role 'outer'
    outer_ways = element[:members]&.select { |m| m[:type] == 'way' && m[:role] == 'outer' }
    return nil unless outer_ways&.any?

    # If we have geometry in members, use it
    all_coords = outer_ways.flat_map do |way|
      way[:geometry]&.map { |node| "#{node[:lon]} #{node[:lat]}" }
    end.compact

    return nil if all_coords.size < 4

    # Create a polygon if we have enough points
    "POLYGON((#{all_coords.join(', ')}))"
  rescue StandardError
    nil
  end

  def calculate_distances_batch(elements_with_geom)
    route_geog = "'#{@route.geom.as_text}'::geography"

    # Build SQL for batch distance calculation
    geom_cases = elements_with_geom.map.with_index do |item, idx|
      "WHEN #{idx} THEN ST_GeomFromText('#{item[:geom]}', 4326)::geography"
    end.join(' ')

    sql = <<~SQL
      SELECT idx, ST_Distance(
        #{route_geog},
        CASE idx #{geom_cases} END
      ) as distance
      FROM generate_series(0, #{elements_with_geom.size - 1}) as idx
    SQL

    distances = ActiveRecord::Base.connection.select_rows(sql)

    distances.each_with_object([]) do |(idx, distance), result|
      result << elements_with_geom[idx.to_i][:element] if distance.to_f < @max_distance
    end
  end

  def osm_id_for_element(element)
    # Create a unique ID combining type and ID
    "#{element[:type]}_#{element[:id]}"
  end

  def build_poi_attributes(element)
    {
      osm_id: osm_id_for_element(element),
      osm_type: element[:type],
      name: element.dig(:tags, :name),
      poi_type: @node_type,
      city: element.dig(:tags, :"addr:city"),
      street: element.dig(:tags, :"addr:street"),
      district: element.dig(:tags, :"addr:suburb"),
      geom: element_to_geometry(element),
      metadata: extract_metadata(element)
    }
  end

  def extract_metadata(element)
    tags = element[:tags] || {}

    case @node_type
    when :toll
      extract_toll_metadata(tags)
    when :fuel
      extract_fuel_metadata(tags)
    when :restaurant
      extract_restaurant_metadata(tags)
    when :hotel
      extract_hotel_metadata(tags)
    else
      # Store all relevant tags for other types
      extract_generic_metadata(tags)
    end
  end

  def extract_toll_metadata(tags)
    {
      # Toll amounts
      toll: tags[:toll],
      charge: tags[:charge],
      toll_hgv: tags[:"toll:hgv"],
      toll_motorcar: tags[:"toll:motorcar"],
      toll_motorcycle: tags[:"toll:motorcycle"],

      # Payment methods
      payment_cash: tags[:"payment:cash"],
      payment_cards: tags[:"payment:cards"],
      payment_electronic: tags[:"payment:electronic_toll_collection"],
      payment_notes: tags[:"payment:notes"],

      # Toll details
      toll_type: tags[:toll_type],
      barrier: tags[:barrier],

      # Operational info
      operator: tags[:operator],
      operator_wikidata: tags[:"operator:wikidata"],
      network: tags[:network],
      ref: tags[:ref],

      # Access info
      opening_hours: tags[:opening_hours],
      lanes: tags[:lanes],
      maxheight: tags[:maxheight],
      maxweight: tags[:maxweight],

      # Contact
      website: tags[:website] || tags[:"contact:website"],
      phone: tags[:phone] || tags[:"contact:phone"],

      # Keep all tags for reference
      all_tags: tags
    }.compact # Remove nil values
  end

  def extract_fuel_metadata(tags)
    {
      brand: tags[:brand],
      operator: tags[:operator],

      # Fuel types
      fuel_diesel: tags[:"fuel:diesel"],
      fuel_octane_95: tags[:"fuel:octane_95"],
      fuel_octane_98: tags[:"fuel:octane_98"],
      fuel_e85: tags[:"fuel:e85"],
      fuel_lpg: tags[:"fuel:lpg"],

      # Amenities
      shop: tags[:shop],
      car_wash: tags[:car_wash],
      compressed_air: tags[:compressed_air],
      vacuum_cleaner: tags[:vacuum_cleaner],

      # Services
      atm: tags[:atm],
      toilets: tags[:toilets],
      restaurant: tags[:restaurant],

      # Hours & contact
      opening_hours: tags[:opening_hours],
      website: tags[:website],
      phone: tags[:phone],

      all_tags: tags
    }.compact
  end

  def extract_restaurant_metadata(tags)
    {
      cuisine: tags[:cuisine],
      diet_vegetarian: tags[:"diet:vegetarian"],
      diet_vegan: tags[:"diet:vegan"],
      outdoor_seating: tags[:outdoor_seating],
      takeaway: tags[:takeaway],
      delivery: tags[:delivery],
      opening_hours: tags[:opening_hours],
      website: tags[:website],
      phone: tags[:phone],
      wheelchair: tags[:wheelchair],

      all_tags: tags
    }.compact
  end

  def extract_hotel_metadata(tags)
    {
      stars: tags[:stars],
      rooms: tags[:rooms],
      beds: tags[:beds],
      internet_access: tags[:internet_access],
      internet_access_fee: tags[:"internet_access:fee"],
      swimming_pool: tags[:swimming_pool],
      restaurant: tags[:restaurant],
      bar: tags[:bar],
      parking: tags[:parking],
      wheelchair: tags[:wheelchair],
      website: tags[:website],
      phone: tags[:phone],
      email: tags[:email],

      all_tags: tags
    }.compact
  end

  def extract_generic_metadata(tags)
    {
      operator: tags[:operator],
      opening_hours: tags[:opening_hours],
      website: tags[:website],
      phone: tags[:phone],
      wheelchair: tags[:wheelchair],

      all_tags: tags
    }.compact
  end

  def osm_id_for_element(element)
    "#{element[:type]}_#{element[:id]}"
  end

  def latitude_for_element(element)
    case element[:type]
    when 'node'
      element[:lat]
    when 'way', 'relation'
      # Use provided center if available
      if element[:center]
        element[:center][:lat]
      elsif element[:geometry]&.any?
        # Calculate centroid from geometry
        calculate_centroid(element[:geometry])[:lat]
      end
    end
  end

  def longitude_for_element(element)
    case element[:type]
    when 'node'
      element[:lon]
    when 'way', 'relation'
      # Use provided center if available
      if element[:center]
        element[:center][:lon]
      elsif element[:geometry]&.any?
        # Calculate centroid from geometry
        calculate_centroid(element[:geometry])[:lon]
      end
    end
  end

  def calculate_centroid(geometry)
    # Calculate the centroid (center point) from geometry coordinates
    return nil if geometry.empty?

    lats = geometry.map { |point| point[:lat] }.compact
    lons = geometry.map { |point| point[:lon] }.compact

    return nil if lats.empty? || lons.empty?

    {
      lat: lats.sum / lats.size.to_f,
      lon: lons.sum / lons.size.to_f
    }
  end
end
