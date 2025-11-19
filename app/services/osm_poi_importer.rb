# app/services/osm_poi_importer.rb
class OsmPoiImporter
  def self.import_from_overpass(poi, node_type)
    osm_poi = OsmPoi.find_or_initialize_by(osm_id: "#{poi[:type]}_#{poi[:id]}")

    osm_poi.update!(
      osm_type: poi[:type],
      name: poi.dig(:tags, :name),
      poi_type: node_type,
      city: poi.dig(:tags, :'addr:city'),
      street: poi.dig(:tags, :'addr:street'),
      district: poi.dig(:tags, :'addr:suburb'),
      geom: create_geometry(poi),
      metadata: extract_metadata(poi[:tags], node_type)
    )

    osm_poi
  end

  def self.create_geometry(poi)
    case poi['type']
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
    return "POINT(#{poi['center']['lon']} #{poi['center']['lat']})" if poi['center']

    # Otherwise calculate from geometry
    return nil unless poi['geometry']&.any?

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

    case node_type
    when :toll
      extract_toll_metadata(tags)
    when :fuel
      extract_fuel_metadata(tags)
    when :restaurant
      extract_restaurant_metadata(tags)
    when :hotel
      extract_hotel_metadata(tags)
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
      brand: tags['brand'],
      operator: tags['operator'],
      fuel_diesel: tags['fuel:diesel'],
      fuel_octane_95: tags['fuel:octane_95'],
      opening_hours: tags['opening_hours'],
      website: tags['website'],
      phone: tags['phone'],
      all_tags: tags
    }.compact
  end

  def self.extract_restaurant_metadata(tags)
    {
      cuisine: tags[:cuisine],
      opening_hours: tags[:opening_hours],
      website: tags[:website],
      phone: tags[:phone],
      all_tags: tags
    }.compact
  end

  def self.extract_hotel_metadata(tags)
    {
      stars: tags['stars'],
      website: tags['website'],
      phone: tags['phone'],
      all_tags: tags
    }.compact
  end

  def self.extract_generic_metadata(tags)
    {
      operator: tags['operator'],
      opening_hours: tags['opening_hours'],
      website: tags['website'],
      phone: tags['phone'],
      all_tags: tags
    }.compact
  end
end
