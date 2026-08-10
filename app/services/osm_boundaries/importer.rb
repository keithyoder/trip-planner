# frozen_string_literal: true

module OsmBoundaries
  # Persists GeoJSON boundary data (fetched via OsmBoundaries::Client) into
  # Boundary records. Knows nothing about HTTP, redirects, or the
  # osm-boundaries.com API — just how to turn a GeoJSON FeatureCollection
  # into rows.
  #
  # Usage:
  #   importer = OsmBoundaries::Importer.new
  #   importer.fetch_and_import(-1907872, level: 8, hierarchy_prefix: "South_America.Peru.puno.chucuito")
  #
  #   # or, with the persistence step alone, given already-fetched GeoJSON:
  #   importer.import_boundaries(geojson, hierarchy_prefix: "...")
  #
  class Importer
    def initialize(client: Client.new)
      @client = client
    end

    # Fetch a boundary's children from the API and import them in one step.
    #
    # @param osm_id [Integer]
    # @param level [Integer] target admin_level
    # @param hierarchy_prefix [String, nil]
    # @return [Integer] number of boundaries imported
    def fetch_and_import(osm_id, level: 2, hierarchy_prefix: nil)
      geojson = client.fetch_boundary(osm_id, level: level)
      import_boundaries(geojson, hierarchy_prefix: hierarchy_prefix)
    end

    # Import already-fetched GeoJSON boundary data into Boundary records.
    #
    # @param geojson [Hash] parsed GeoJSON (symbolized keys), as returned by Client#fetch_boundary
    # @param hierarchy_prefix [String, nil]
    # @return [Integer] number of boundaries imported
    def import_boundaries(geojson, hierarchy_prefix: nil)
      return 0 if geojson.blank? || geojson[:features].blank?

      count = 0
      factory = RGeo::Geographic.spherical_factory(srid: 4326)

      geojson[:features].each do |feature|
        props = feature[:properties]

        hierarchy = if hierarchy_prefix
                      "#{hierarchy_prefix}.#{(props[:name_en] || props[:name]).parameterize.underscore}"
                    else
                      (props[:name_en] || props[:name]).parameterize.underscore
                    end

        geometry = RGeo::GeoJSON.decode(feature.to_json, json_parser: :json, geo_factory: factory)

        boundary = Boundary.find_or_initialize_by(osm_id: props[:osm_id])

        attributes = {
          name: props[:name],
          hierarchy: hierarchy,
          level: props[:admin_level]
        }

        attributes[:admin_node_id] = props[:admin_centre_node_id] if props[:admin_centre_node_id]

        if props[:admin_centre_node_lng] && props[:admin_centre_node_lat]
          attributes[:admin_point] = factory.point(
            props[:admin_centre_node_lng],
            props[:admin_centre_node_lat]
          )
        end

        attributes[:geom] = geometry.geometry if geometry

        boundary.update!(attributes)
        count += 1

        puts "Imported: #{props[:name]} (OSM ID: #{props[:osm_id]}, Level: #{props[:admin_level]})"
      end

      puts "Successfully imported #{count} boundaries"
      count
    rescue StandardError => e
      puts "Error importing boundaries: #{e.message}"
      puts e.backtrace.first(5)
      raise
    end

    private

    attr_reader :client
  end
end
