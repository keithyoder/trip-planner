# frozen_string_literal: true

class OsmPoiImporter
  def self.import_from_overpass(poi, node_type)
    poi = poi.deep_symbolize_keys if poi.respond_to?(:deep_symbolize_keys)

    osm_id = "#{poi[:type]}_#{poi[:id]}"

    attributes = {
      osm_id: osm_id,
      osm_type: poi[:type],
      name: poi.dig(:tags, :name),
      poi_type: OsmPoi.poi_types[node_type.to_sym],
      city: poi.dig(:tags, :'addr:city'),
      street: poi.dig(:tags, :'addr:street'),
      district: poi.dig(:tags, :'addr:suburb'),
      geom: create_geometry(poi),
      metadata: extract_metadata(poi[:tags], node_type)
    }

    OsmPoi.upsert(
      attributes,
      unique_by: :osm_id,
      update_only: attributes.keys - [:osm_id]
    )

    OsmPoi.find_by(osm_id: osm_id)
  end

  # def self.import_from_overpass(poi, node_type)
  #   # Normalize to symbol keys for consistency
  #   poi = poi.deep_symbolize_keys if poi.respond_to?(:deep_symbolize_keys)

  #   osm_poi = OsmPoi.find_or_initialize_by(osm_id: "#{poi[:type]}_#{poi[:id]}")

  #   osm_poi.update!(
  #     osm_type: poi[:type],
  #     name: poi.dig(:tags, :name),
  #     poi_type: node_type,
  #     city: poi.dig(:tags, :'addr:city'),
  #     street: poi.dig(:tags, :'addr:street'),
  #     district: poi.dig(:tags, :'addr:suburb'),
  #     geom: create_geometry(poi),
  #     metadata: extract_metadata(poi[:tags], node_type)
  #   )

  #   osm_poi
  # end

  def self.create_geometry(poi)
    case poi[:type]
    when 'node'
      # Nodes already have a point
      "POINT(#{poi[:lon]} #{poi[:lat]})"
    when 'way'
      # Calculate centroid for ways
      calculate_centroid_from_way(poi)
    when 'relation'
      # Use provided center or calculate centroid for relations
      calculate_centroid_from_relation(poi)
    end
  end

  def self.calculate_centroid_from_way(poi)
    # Use provided center if available
    return "POINT(#{poi[:center][:lon]} #{poi[:center][:lat]})" if poi[:center]

    # Otherwise calculate from geometry
    return nil unless poi[:geometry]&.any?

    lats = poi[:geometry].map { |node| node[:lat] }.compact
    lons = poi[:geometry].map { |node| node[:lon] }.compact

    return nil if lats.empty? || lons.empty?

    avg_lat = lats.sum / lats.size.to_f
    avg_lon = lons.sum / lons.size.to_f

    "POINT(#{avg_lon} #{avg_lat})"
  end

  def self.calculate_centroid_from_relation(poi)
    # Use provided center if available
    return "POINT(#{poi[:center][:lon]} #{poi[:center][:lat]})" if poi[:center]

    # Otherwise calculate from geometry
    return nil unless poi[:geometry]&.any?

    lats = poi[:geometry].map { |p| p[:lat] }.compact
    lons = poi[:geometry].map { |p| p[:lon] }.compact

    return nil if lats.empty? || lons.empty?

    avg_lat = lats.sum / lats.size.to_f
    avg_lon = lons.sum / lons.size.to_f

    "POINT(#{avg_lon} #{avg_lat})"
  end

  def self.extract_metadata(tags, node_type)
    return {} unless tags

    case node_type.to_sym
    when :toll, :barrier
      extract_toll_metadata(tags)
    when :fuel
      extract_fuel_metadata(tags)
    when :restaurant
      extract_restaurant_metadata(tags)
    when :accommodation
      extract_hotel_metadata(tags)
    when :tourism
      extract_tourism_metadata(tags)
    when :park
      extract_park_metadata(tags)
    else
      extract_generic_metadata(tags)
    end
  end

  def self.extract_toll_metadata(tags)
    {
      toll: tags[:toll],
      charge: tags[:charge],
      toll_hgv: tags[:'toll:hgv'],
      toll_motorcar: tags[:'toll:motorcar'],
      toll_motorcycle: tags[:'toll:motorcycle'],
      payment_cash: tags[:'payment:cash'],
      payment_cards: tags[:'payment:cards'],
      payment_electronic: tags[:'payment:electronic_toll_collection'],
      toll_type: tags[:toll_type],
      operator: tags[:operator],
      opening_hours: tags[:opening_hours],
      website: tags[:website],
      phone: tags[:phone],
      all_tags: tags
    }.compact
  end

  def self.extract_fuel_metadata(tags)
    {
      brand: tags[:brand],
      operator: tags[:operator],
      fuel_diesel: tags[:'fuel:diesel'],
      fuel_octane_95: tags[:'fuel:octane_95'],
      opening_hours: tags[:opening_hours],
      website: tags[:website],
      phone: tags[:phone],
      all_tags: tags
    }.compact
  end

  def self.extract_restaurant_metadata(tags)
    {
      cuisine: tags[:cuisine],
      diet_vegetarian: tags[:'diet:vegetarian'],
      diet_vegan: tags[:'diet:vegan'],
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

  def self.extract_hotel_metadata(tags)
    {
      stars: tags[:stars],
      rooms: tags[:rooms],
      beds: tags[:beds],
      internet_access: tags[:internet_access],
      internet_access_fee: tags[:'internet_access:fee'],
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

  def self.extract_tourism_metadata(tags)
    {
      tourism_type: tags[:tourism],
      historic_type: tags[:historic],
      name_local: tags[:'name:es'] || tags[:'name:pt'],
      description: tags[:description],
      wikipedia: tags[:wikipedia],
      wikidata: tags[:wikidata],
      opening_hours: tags[:opening_hours],
      fee: tags[:fee],
      entrance_fee: tags[:charge],
      website: tags[:website] || tags[:'contact:website'],
      phone: tags[:phone] || tags[:'contact:phone'],
      wheelchair: tags[:wheelchair],
      operator: tags[:operator],
      all_tags: tags
    }.compact
  end

  def self.extract_generic_metadata(tags)
    {
      operator: tags[:operator],
      opening_hours: tags[:opening_hours],
      website: tags[:website],
      phone: tags[:phone],
      wheelchair: tags[:wheelchair],
      all_tags: tags
    }.compact
  end

  def self.extract_park_metadata(tags)
    {
      leisure_type: tags[:leisure],
      description: tags[:description],
      wikipedia: tags[:wikipedia],
      wikidata: tags[:wikidata],
      website: tags[:website] || tags[:'contact:website'],
      opening_hours: tags[:opening_hours],
      fee: tags[:fee],
      operator: tags[:operator],
      wheelchair: tags[:wheelchair],
      dog: tags[:dog],
      all_tags: tags
    }.compact
  end
end
