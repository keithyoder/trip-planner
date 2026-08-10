# frozen_string_literal: true

require 'net/http'
require 'zlib'
require 'stringio'
require 'json'

module OsmBoundaries
  # Thin HTTP client for osm-boundaries.com's download API. Knows nothing
  # about Boundary or how the data gets persisted — just how to fetch a
  # given OSM boundary's GeoJSON, including following the async "building
  # your file" redirect/poll chain their docs describe.
  #
  # Usage:
  #   client = OsmBoundaries::Client.new
  #   geojson = client.fetch_boundary(-1907872, level: 8) # => Hash (symbolized keys)
  #
  class Client
    BASE_URL = 'https://osm-boundaries.com/'
    DB_VERSION = 'osm20260706'
    MAX_REDIRECTS = 10

    def initialize(access_token: ENV['OSM_BOUNDARIES_TOKEN'], base_url: BASE_URL)
      @access_token = access_token
      @base_url = base_url
    end

    # @param osm_id [Integer]
    # @param level [Integer] target admin_level
    # @return [Hash] parsed GeoJSON (symbolized keys)
    # @raise [RuntimeError] if the API returns a non-success, non-gzip response
    def fetch_boundary(osm_id, level: 2)
      uri = URI.join(base_url, 'api/v1/download')
      uri.query = URI.encode_www_form(
        db: DB_VERSION,
        osmIds: osm_id,
        recursive: false,
        minAdminLevel: level,
        maxAdminLevel: level,
        boundary: 'administrative',
        format: 'GeoJSON',
        srid: 4326
      )
      perform_request(uri, Net::HTTP::Get.new(uri))
    end

    private

    attr_reader :access_token, :base_url

    def perform_request(uri, req, limit: MAX_REDIRECTS)
      raise "Too many redirects fetching #{uri}" if limit <= 0

      req['X-OSMB-Api-Key'] = access_token

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }

      if response.is_a?(Net::HTTPRedirection)
        # Resolve relative to the URI we just requested — avoids a
        # double-slash bug from naively concatenating strings when both
        # base_url and the Location header start/end with a slash (which
        # some strict routers 404 on instead of collapsing).
        location = URI.join(uri, response['location'])
        puts "  Redirecting to: #{location}"

        # Async export jobs redirect to a polling URL while the file is
        # being built (per their docs: "it may take some time for our
        # systems to build your file"). Pause briefly between polls
        # instead of hammering the endpoint immediately on every hop.
        sleep(2) if location.to_s.include?('wait') || location.to_s.include?('exportId')

        return perform_request(location, Net::HTTP::Get.new(location), limit: limit - 1)
      end

      parse_response(response)
    end

    def parse_response(res)
      content_type = res['content-type']
      content_disp = res['content-disposition']

      if content_type&.include?('gzip') || content_disp&.include?('.geojson.gz')
        geojson = Zlib::GzipReader.new(StringIO.new(res.body)).read
        return JSON.parse(geojson, symbolize_names: true)
      end

      # Anything else is an error response, not a missing/pending result —
      # surface it rather than silently returning nil.
      raise "osm-boundaries.com API error (HTTP #{res.code}): #{res.body.to_s[0..500]}"
    end
  end
end
