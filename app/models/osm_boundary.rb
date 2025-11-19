# frozen_string_literal: true

require 'net/http'
require 'zlib'
require 'stringio'
require 'json'

class OsmBoundary
  attr_accessor :url

  BASE_URL = 'https://osm-boundaries.com/'

  def initialize(access_token = nil, url = nil)
    @access_token = access_token || ENV['OSM_BOUNDARIES_TOKEN']
    @url = url || BASE_URL
  end

  def get(path, query = {})
    uri = URI("#{@url}#{path}")
    uri.query = URI.encode_www_form(query) unless query == {}
    perform_request(uri, Net::HTTP::Get.new(uri))
  end

  def fetch_boundary(osm_id, level: 2)
    query = {
      db: 'osm20250407',
      osmIds: osm_id,
      recursive: false,
      minAdminLevel: level,
      maxAdminLevel: level,
      boundary: 'administrative',
      format: 'GeoJSON',
      srid: 4326
    }
    path = 'api/v1/download'
    get(path, query)
  end

  # Fetch and import boundaries in one step
  def fetch_and_import(osm_id, level: 2, hierarchy_prefix: nil)
    while (geojson = fetch_boundary(osm_id, level: level)).blank?
      puts "Retrying fetch for OSM ID: #{osm_id} at level: #{level}..."
      sleep(10)
    end
    import_boundaries(geojson, hierarchy_prefix: hierarchy_prefix)
  end

  # Import GeoJSON boundaries into the database
  def import_boundaries(geojson, hierarchy_prefix: nil)
    return 0 if geojson.blank? || geojson[:features].blank?

    count = 0
    factory = RGeo::Geographic.spherical_factory(srid: 4326)

    geojson[:features].each do |feature|
      props = feature[:properties]

      # Build hierarchy string
      hierarchy = if hierarchy_prefix
                    "#{hierarchy_prefix}.#{(props[:name_en] || props[:name]).parameterize.underscore}"
                  else
                    (props[:name_en] || props[:name]).parameterize.underscore
                  end

      # Parse geometry using RGeo
      geometry = RGeo::GeoJSON.decode(feature.to_json, json_parser: :json, geo_factory: factory)

      # Create or update boundary
      boundary = Boundary.find_or_initialize_by(osm_id: props[:osm_id])

      attributes = {
        name: props[:name],
        hierarchy: hierarchy,
        level: props[:admin_level]
      }

      # Add optional fields if present
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

  def perform_request(uri, req, body = nil, limit = 5)
    raise ArgumentError, 'Too many redirects' if limit <= 0

    req.body = body.to_json unless body.nil?
    req['X-OSMB-Api-Key'] = @access_token

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(req)
    end

    if response.is_a?(Net::HTTPRedirection)
      location = URI("#{BASE_URL}#{response['location']}")
      puts "  Redirecting to: #{location}"

      # Preserve same HTTP method (important for 307/308)
      # new_req = req.class.new(new_uri)
      # new_req.body = req.body
      # new_req['X-OSMB-Api-Key'] = @access_token

      response = Net::HTTP.start(location.hostname, location.port, use_ssl: true) do |http|
        http.request(Net::HTTP::Get.new(location))
      end
    end
    parse_response(response)
  end

  def parse_response(res)
    content_type = res['content-type']
    content_disp = res['content-disposition']

    # 💾 CASE 1: Binary file (likely .geojson.gz)
    return unless content_type&.include?('gzip') || content_disp&.include?('.geojson.gz')

    # filename = content_disp & [/filename="?([^"]+)"?/, 1] || 'download.geojson.gz'
    # File.open(filename, 'wb') { |f| f.write(res.body) }
    # puts "Saved compressed GeoJSON to: #{filename}"

    # Optionally, decompress it and return parsed JSON
    geojson = Zlib::GzipReader.new(StringIO.new(res.body)).read
    JSON.parse(geojson, symbolize_names: true)
  end
end
