module SpeedBumps
  class OsmMatcher
    API_URL = URI('https://overpass-api.de/api/interpreter')
    MATCH_RADIUS_METERS = 30
    OPEN_TIMEOUT = 10
    READ_TIMEOUT = 60

    def initialize(match_radius_meters: MATCH_RADIUS_METERS)
      @match_radius_meters = match_radius_meters
    end

    # @param events [Array<Hash>] output of SpeedBumps::Detector#detect
    # @return [Array<Hash>] the subset with no matching OSM node nearby
    def unmatched(events)
      return [] if events.empty?

      existing_nodes = fetch_existing_nodes(events)
      events.reject { |event| existing_node_nearby?(event, existing_nodes) }
    end

    private

    attr_reader :match_radius_meters

    # One request covering every event's location, instead of one request
    # per event -- both far faster and more polite to Overpass's public
    # instance, which explicitly discourages rapid small queries.
    def fetch_existing_nodes(events)
      unions = events.map { |e| "node(around:#{match_radius_meters},#{e[:lat]},#{e[:lon]})[traffic_calming];" }.join
      query = "[out:json][timeout:60];(#{unions});out body;"

      response = query_overpass(query)
      (response['elements'] || []).map { |el| [el['lat'], el['lon']] }
    rescue StandardError => e
      Rails.logger.warn("[SpeedBumps::OsmMatcher] Overpass query failed: #{e.message}")
      [] # fail open -- better to export a possible duplicate than silently drop a real find
    end

    def existing_node_nearby?(event, existing_nodes)
      existing_nodes.any? do |lat, lon|
        distance_meters(event[:lat], event[:lon], lat, lon) <= match_radius_meters
      end
    end

    def distance_meters(lat1, lon1, lat2, lon2)
      Geocoder::Calculations.distance_between([lat1, lon1], [lat2, lon2], units: :km) * 1000
    end

    def query_overpass(query)
      http = Net::HTTP.new(API_URL.host, API_URL.port)
      http.use_ssl = true
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT
      response = http.post(API_URL.path, "data=#{URI.encode_www_form_component(query)}",
                           'Content-Type' => 'application/x-www-form-urlencoded')
      JSON.parse(response.body)
    end
  end
end
