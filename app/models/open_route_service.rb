# frozen_string_literal: true

require 'net/http'

class OpenRouteService
  attr_accessor :url

  def initialize(access_token = nil, url = nil)
    @access_token = access_token || ENV['OPEN_ROUTE_SERVICE_TOKEN']
    @url = url || 'https://api.openrouteservice.org'
  end

  def get(path, query = {})
    uri = URI("#{@url}#{path}")
    uri.query = URI.encode_www_form(query) unless query == {}
    perform_request(uri, Net::HTTP::Get.new(uri))
  end

  def patch(path, body)
    uri = URI("#{@url}#{path}")
    perform_request(uri, Net::HTTP::Patch.new(uri), body)
  end

  def post(path, body)
    uri = URI("#{@url}#{path}")
    perform_request(uri, Net::HTTP::Post.new(uri), body)
  end

  def put(path, body)
    uri = URI("#{@url}#{path}")
    perform_request(uri, Net::HTTP::Put.new(uri), body)
  end

  private

  def perform_request(uri, req, body = nil)
    req.body = body.to_json unless body.nil?
    req['Authorization'] = @access_token
    req['Content-type'] = 'application/json'
    parse_response(
      Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
        http.request(req)
      end
    )
  end

  def parse_response(res)
    parsed_response = JSON.parse(res.body, symbolize_names: true) if res.body.present?
    unless res.is_a?(Net::HTTPSuccess) && (parsed_response.blank? || parsed_response.keys.exclude?(:errors))
      raise StandardError, parsed_response
    end

    parsed_response
  end
end
