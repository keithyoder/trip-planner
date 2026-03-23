# frozen_string_literal: true

require 'net/http'

class Overpass
  class RateLimitError < StandardError; end
  class QueryError < StandardError; end

  attr_reader :response

  API_URL = URI('https://overpass-api.de/api/interpreter').freeze
  RETRY_ATTEMPTS = 3
  RETRY_DELAY_SECONDS = 15

  CATEGORIES = {
    fuel: { query: "'amenity'='fuel'", distance: 500, types: %i[node way] },
    border_crossing: { query: "'barrier'='border_control'", distance: 10, types: %i[node way] },
    ferry: { query: "'amenity'='ferry_terminal'", distance: 5, types: %i[node way] },
    restaurant: { query: "'amenity'~'restaurant|fast_food|pub|ice_cream'", distance: 2000, types: %i[node way] },
    bank: { query: "'amenity'~'bank|money_transfer'", distance: 1000, types: %i[node way] },
    accommodation: {
      query: "'tourism'~'hotel|hostel|motel|guest_house|apartment|chalet|camp_site|caravan_site|wilderness_hut|alpine_hut'",
      distance: 20_000,
      types: %i[node way]
    },
    toll: { query: "'barrier'='toll_booth'", distance: 5, types: %i[node way] },
    parking: { query: "'amenity'='parking'", distance: 100, types: %i[way relation] },
    park: { query: "'leisure'='park'", distance: 500, types: %i[way relation] },
    rest_area: { query: "'highway'='rest_area'", distance: 100, types: %i[node way] },
    barrier: { query: ["'barrier'='lift_gate'", "'amenity'='shelter'"], distance: 10, types: %i[node way] },
    tourism: {
      query: "'tourism']['tourism'!='hotel']['tourism'!='hostel']['tourism'!='motel']['tourism'!='guest_house'",
      distance: 40_000,
      types: %i[node way relation]
    },
    place: {
      query: "'place'~'city|town|village|hamlet'",
      distance: 100_000,
      types: %i[node]
    },
    laundry: { query: "'shop'~'laundry|dry_cleaning'", distance: 1000, types: %i[node way] }
  }.freeze

  def initialize(route_id, node_type)
    @node_type = node_type
    @max_distance = CATEGORIES.fetch(node_type).fetch(:distance)
    @route = Route.with_bbox.find(route_id)

    query = build_query
    Rails.logger.debug "[Overpass] Query: #{query}"

    @response = query_with_retry(query)
  end

  def close_to_route
    @close_to_route ||= begin
      elements_with_geom = response[:elements].filter_map do |element|
        geom = element_to_geometry(element)
        next unless geom

        { element: element, geom: geom }
      end

      return [] if elements_with_geom.empty?

      calculate_distances_batch(elements_with_geom)
    end
  end

  def import
    close_to_route.each { |element| OsmPoiImporter.import_from_overpass(element, @node_type) }
  end

  def pois_for_map
    close_to_route.map do |poi|
      {
        osm_id: osm_id_for_element(poi),
        lat: coordinate_for_element(poi, :lat),
        lon: coordinate_for_element(poi, :lon),
        name: poi.dig(:tags, :name),
        street: poi.dig(:tags, :"addr:street"),
        city: poi.dig(:tags, :"addr:city"),
        toll_amount: poi.dig(:tags, :toll) || poi.dig(:tags, :charge),
        operator: poi.dig(:tags, :operator)
      }
    end
  end

  private

  # -- Query ---------------------------------------------------------------

  def build_query
    types = CATEGORIES[@node_type][:types]
    queries_list = Array(CATEGORIES[@node_type][:query])

    # Expand bbox by max_distance so Overpass returns candidates
    # that are up to that distance from the route boundary.
    # 1 degree ≈ 111,000 m — close enough for a search buffer.
    buffer_deg = @max_distance / 111_000.0

    bbox = "(#{@route.bbox_s - buffer_deg},#{@route.bbox_w - buffer_deg},#{@route.bbox_n + buffer_deg},#{@route.bbox_e + buffer_deg})"

    queries = queries_list.flat_map do |filter|
      types.map { |type| "#{type}[#{filter}]#{bbox}" }
    end

    "[out:json][timeout:90];(#{queries.join(';')};);out body geom;"
  end

  def query_with_retry(query)
    RETRY_ATTEMPTS.times do |attempt|
      return perform_request(query)
    rescue QueryError => e
      handle_error(e, attempt)
    rescue JSON::ParserError => e
      handle_error(e, attempt)
    end
  end

  def perform_request(query)
    http = Net::HTTP.new(API_URL.host, API_URL.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE if Rails.env.development?

    response = http.post(
      API_URL.path,
      "data=#{URI.encode_www_form_component(query)}",
      'Accept' => 'application/json',
      'Content-Type' => 'application/x-www-form-urlencoded'
    )

    unless response.is_a?(Net::HTTPSuccess)
      Rails.logger.error "[Overpass] HTTP #{response.code}: #{response.body.truncate(500)}"
      raise QueryError, "Overpass returned HTTP #{response.code}"
    end

    JSON.parse(response.body, symbolize_names: true)
  end

  def handle_error(error, attempt)
    Rails.logger.warn "[Overpass] Error on attempt #{attempt + 1}/#{RETRY_ATTEMPTS}: #{error.message}"

    raise RateLimitError, "Overpass API failed after #{RETRY_ATTEMPTS} attempts" if attempt == RETRY_ATTEMPTS - 1

    Rails.logger.info "[Overpass] Retrying in #{RETRY_DELAY_SECONDS}s..."
    sleep(RETRY_DELAY_SECONDS)
  end

  # -- Geometry ------------------------------------------------------------

  def element_to_geometry(element)
    case element[:type]
    when 'node'     then node_to_point(element)
    when 'way'      then way_to_geometry(element)
    when 'relation' then relation_to_geometry(element)
    end
  rescue StandardError => e
    Rails.logger.warn "[Overpass] Failed to build geometry for #{element[:type]} #{element[:id]}: #{e.message}"
    nil
  end

  def node_to_point(element)
    return nil unless element[:lat] && element[:lon]

    "POINT(#{element[:lon]} #{element[:lat]})"
  end

  def way_to_geometry(element)
    coords = element[:geometry]&.map { |n| "#{n[:lon]} #{n[:lat]}" }
    return nil if coords.nil? || coords.size < 2

    first = element[:geometry].first
    last = element[:geometry].last
    closed = coords.size >= 4 && first[:lat] == last[:lat] && first[:lon] == last[:lon]

    closed ? "POLYGON((#{coords.join(', ')}))" : "LINESTRING(#{coords.join(', ')})"
  end

  def relation_to_geometry(element)
    return "POINT(#{element[:center][:lon]} #{element[:center][:lat]})" if element[:center]

    outer_ways = element[:members]&.select { |m| m[:type] == 'way' && m[:role] == 'outer' }
    return nil unless outer_ways&.any?

    coords = outer_ways.flat_map { |w| w[:geometry]&.map { |n| "#{n[:lon]} #{n[:lat]}" } }.compact
    return nil if coords.size < 4

    # Ensure the ring is closed — OSM relation outer ways concatenated in order
    # rarely end where they started, so we must explicitly close the ring.
    # ST_GeomFromText raises a parse error (before ST_MakeValid can help) if
    # the ring is not closed.
    coords << coords.first unless coords.first == coords.last

    "POLYGON((#{coords.join(', ')}))"
  rescue StandardError
    nil
  end

  def valid_wkt?(wkt)
    factory = RGeo::Geographic.spherical_factory(srid: 4326)
    RGeo::WKRep::WKTParser.new(factory, support_ewkt: false).parse(wkt)
    true
  rescue StandardError
    false
  end

  def calculate_distances_batch(elements_with_geom)
    route_geog = "'#{@route.geom.as_text}'::geography"

    # Pre-filter elements whose WKT is invalid in Ruby before sending to
    # PostgreSQL. ST_GeomFromText raises a parse error that cannot be caught
    # from within SQL (ST_MakeValid runs after parsing, not before).
    valid_elements = elements_with_geom.select do |item|
      next true if valid_wkt?(item[:geom])

      Rails.logger.warn '[Overpass] Skipping element with invalid WKT ' \
                        "(#{item.dig(:element, :type)} #{item.dig(:element, :id)})"
      false
    end

    return [] if valid_elements.empty?

    geom_cases = valid_elements.each_with_index.map do |item, idx|
      "WHEN #{idx} THEN ST_MakeValid(ST_GeomFromText('#{item[:geom]}', 4326))::geography"
    end.join(' ')

    sql = <<~SQL
      SELECT idx, ST_Distance(
        #{route_geog},
        CASE idx #{geom_cases} END
      ) AS distance
      FROM generate_series(0, #{valid_elements.size - 1}) AS idx
    SQL

    ActiveRecord::Base.connection.select_rows(sql).each_with_object([]) do |(idx, distance), result|
      result << valid_elements[idx.to_i][:element] if distance.to_f < @max_distance
    end
  end

  # -- Element helpers -----------------------------------------------------

  def osm_id_for_element(element)
    "#{element[:type]}_#{element[:id]}"
  end

  def coordinate_for_element(element, axis)
    case element[:type]
    when 'node'
      element[axis]
    when 'way', 'relation'
      element.dig(:center, axis) || calculate_centroid(element[:geometry])&.dig(axis)
    end
  end

  def calculate_centroid(geometry)
    return nil if geometry.blank?

    values = geometry.filter_map { |p| { lat: p[:lat], lon: p[:lon] } if p[:lat] && p[:lon] }
    return nil if values.empty?

    { lat: values.sum { |v| v[:lat] } / values.size.to_f,
      lon: values.sum { |v| v[:lon] } / values.size.to_f }
  end
end
