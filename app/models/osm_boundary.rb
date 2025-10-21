# frozen_string_literal: true

require 'net/http'

class OsmBoundary
  attr_accessor :url

  def initialize(access_token = nil, url = nil)
    @access_token = access_token || ENV['OSM_BOUNDARIES_TOKEN']
    @url = url || 'https://osm-boundaries.com/'
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
    path = "api/v1/download"
    get(path, query)
  end

  private

  def perform_request(uri, req, body = nil)
    req.body = body.to_json unless body.nil?
    req['X-OSMB-Api-Key'] = @access_token
    #req['Content-type'] = 'application/json'
    parse_response(
      Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
        http.request(req)
      end
    )
  end

  def parse_response(res)
    puts res.body
    parsed_response = JSON.parse(res.body, symbolize_names: true) if res.body.present?
    unless res.is_a?(Net::HTTPSuccess) && (parsed_response.blank? || parsed_response.keys.exclude?(:errors))
      raise StandardError, parsed_response
    end

    parsed_response
  end

end
