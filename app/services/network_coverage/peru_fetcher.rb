# frozen_string_literal: true

require 'net/http'
require 'json'
require 'timeout'
require 'erb'

module NetworkCoverage
  # Fetches Claro Peru coverage by downloading pre-generated static GeoJSON
  # files, one per district, rather than point-sampling a query API like
  # every other fetcher in this module. Claro Peru's coverage site serves
  # files named DEPARTAMENTO_PROVINCIA_DISTRITO_<suffix>.geojson under
  # per-layer folders — there is no queryable API here.
  #
  # Two layers are known:
  #   - "cobertura_movil_4G_PE"           => GARANTIZADA (guaranteed) — plan around this
  #   - "cobertura_movil_4G_adicional_PE" => CAPACIDAD_ADICIONAL (non-guaranteed,
  #     line-of-sight radio circles) — treat as "voice/WhatsApp might work", not real data coverage
  #
  # District discovery is a plain hierarchy lookup (via nlevel(hierarchy)
  # rather than the `level`/admin_level column, since Peru's admin_level
  # numbering wasn't confirmed) scoped to whatever `boundary` you pass in —
  # e.g. a department or province you've already picked. No spatial query
  # against the route: `boundary` IS the scope, so every district under it
  # gets fetched, full stop. Pick a boundary tight enough (a department or
  # province, not "Peru" itself) that this doesn't pull in districts your
  # route never actually reaches.
  #
  # KNOWN UNCONFIRMED ASSUMPTIONS — verify before trusting results broadly:
  #   1. The GARANTIZADA folder/filename suffix below is a GUESS, built by
  #      analogy with the confirmed ADICIONAL pattern. It has not been
  #      tested against a real URL. Confirm with one real district before
  #      relying on cobertura_movil_4G_PE.
  #
  # RESOLVED: accented names (e.g. "Caravelí", "Iñapari") are transliterated
  # to plain ASCII before building the filename — confirmed via a real
  # working URL (AREQUIPA_CARAVELI_JAQUI_..., not CARAVELÍ). Note this
  # means "Ñ" also becomes "N" (Rails' default transliteration strips it
  # like any other diacritic) — not separately confirmed against a real
  # Ñ-containing filename, but consistent with the confirmed Í-stripping
  # behavior, so treated as correct until shown otherwise.
  #
  # Usage:
  #   puno = Boundary.find_unambiguous("Peru/Puno") # or by numeric id if the name is ambiguous
  #   PeruFetcher.new(trip_track: trip.trip_track, layer: "cobertura_movil_4G_adicional_PE", boundary: puno).call
  #
  class PeruFetcher
    PROVIDER = 'claro'
    BASE = 'https://mapa.claromarketingcloud.pe/ruta_kmz/ZONAS_COBERTURA/4G'

    # NOTE: GARANTIZADA folder/suffix is an unconfirmed guess — see class comment.
    LAYER_CONFIG = {
      'cobertura_movil_4G_PE' => { folder: 'GARANTIZADA', suffix: '4G_GARANTIZADA' },
      'cobertura_movil_4G_adicional_PE' => { folder: 'ADICIONAL', suffix: '4G_CAPACIDAD_ADICIONAL' }
    }.freeze

    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 10
    HARD_TIMEOUT = 20
    MAX_RETRIES = 2
    REQUEST_DELAY = 0.2

    def initialize(trip_track:, layer:, boundary: nil)
      @trip_track = trip_track
      @layer = layer
      @boundary = boundary # required: districts are looked up under this Boundary via hierarchy, no spatial query
      @layer_config = LAYER_CONFIG.fetch(layer) do
        raise ArgumentError, "Unknown Peru layer #{layer.inspect}, expected one of #{LAYER_CONFIG.keys}"
      end
    end

    def call
      found = districts
      if found.empty?
        warn "No districts found for this trip#{boundary ? " under #{boundary.name}" : ''} — " \
             'check that district-level Boundary rows exist and actually intersect the route.'
        return
      end

      warn "#{found.size} district(s) to check: #{found.map(&:name).join(', ')}"

      found.each_with_index do |district, i|
        url = file_url(district)
        status, detail = fetch_and_upsert(district, url)
        warn "  [#{i + 1}/#{found.size}] #{district.name}: #{status_message(status, detail)} (#{url})"
        sleep(REQUEST_DELAY)
        yield(i + 1, found.size, district.name, status, detail) if block_given?
      end
    end

    private

    def status_message(status, detail)
      case status
      when :fetched then "fetched, #{detail} feature(s)"
      when :no_coverage then 'no coverage file for this district (404 — expected for most)'
      when :empty_response then 'response OK but had no usable features'
      when :error then "ERROR: #{detail}"
      end
    end

    attr_reader :trip_track, :layer, :boundary, :layer_config

    # Districts (depth = Peru's depth + 3) under `boundary`. No spatial
    # query against the route — `boundary` is the scope (e.g. a single
    # department or province you've already picked), so this is a plain
    # hierarchy lookup: every district under that boundary, full stop.
    def districts
      @districts ||= begin
        peru = ::Boundary.find_unambiguous('6')
        target_depth = peru.hierarchy.to_s.split('.').size + 3

        if boundary.nil?
          raise ArgumentError,
                'PeruFetcher requires a boundary (e.g. a department or province) to scope the district lookup to'
        end

        ::Boundary
          .where('hierarchy <@ ?', boundary.hierarchy)
          .where('nlevel(hierarchy) = ?', target_depth)
          .to_a
      end
    end

    # [departamento, provincia, distrito] names, transliterated to plain
    # ASCII (accents stripped — e.g. "Caravelí" => "CARAVELI") and upcased
    # with spaces replaced by underscores, matching Claro's filename
    # convention (confirmed via AREQUIPA_CARAVELI_JAQUI_4G_CAPACIDAD_ADICIONAL —
    # note plain "I", not accented "Í", despite the real district name
    # being "Caravelí"/"Jaquí").
    def filename_parts(district)
      depth = district.hierarchy.to_s.split('.').size
      departamento, provincia = ::Boundary
                                .where('hierarchy @> ?', district.hierarchy)
                                .where('nlevel(hierarchy) IN (?, ?)', depth - 2, depth - 1)
                                .order(Arel.sql('nlevel(hierarchy)'))
                                .pluck(:name)

      [departamento, provincia, district.name].map { |n| ActiveSupport::Inflector.transliterate(n).upcase.tr(' ', '_') }
    end

    def file_url(district)
      dept, prov, dist = filename_parts(district)
      filename = "#{dept}_#{prov}_#{dist}_#{layer_config[:suffix]}.geojson"
      "#{BASE}/#{layer_config[:folder]}/#{ERB::Util.url_encode(filename)}"
    end

    def fetch_and_upsert(district, url)
      body = fetch_body(url)
      return [:no_coverage, nil] if body.nil?

      geojson = JSON.parse(body)
      features = geojson['type'] == 'FeatureCollection' ? geojson['features'] : [geojson]

      count = 0
      features.each do |feature|
        count += 1 if upsert_feature(district, feature)
      end

      count.positive? ? [:fetched, count] : [:empty_response, nil]
    rescue JSON::ParserError => e
      [:error, "invalid JSON response: #{e.message}"]
    end

    def upsert_feature(district, feature)
      return false if feature['geometry'].nil?

      source_id = feature.dig('properties', 'OBJECTID') ||
                  feature.dig('properties', 'ESRI_OID') ||
                  feature.dig('properties', 'fid')

      if source_id.nil?
        warn "  [warn] #{district.name}: feature with no identifiable id, skipping"
        return false
      end

      # Prefix with district.id: OBJECTID/fid are per-source-file values and
      # aren't guaranteed unique across Claro's separate per-district files.
      Feature.upsert_from_geojson!(
        trip: trip_track.trip,
        provider: PROVIDER,
        layer: layer,
        source_feature_id: "#{district.id}_#{source_id}",
        geojson_geometry: feature['geometry']
      )
      true
    end

    def fetch_body(url, attempt: 0)
      uri = URI(url)
      Timeout.timeout(HARD_TIMEOUT, Timeout::Error, "hard timeout fetching #{url}") do
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.open_timeout = OPEN_TIMEOUT
        http.read_timeout = READ_TIMEOUT
        response = http.get(uri.request_uri)

        return response.body if response.is_a?(Net::HTTPSuccess)
        return nil if response.code.to_i == 404 # expected: no coverage file for this district/layer

        warn "  [warn] #{url} returned HTTP #{response.code}"
        nil
      end
    rescue Timeout::Error, Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET, Errno::ETIMEDOUT, SocketError,
           EOFError => e
      if attempt < MAX_RETRIES
        warn "  [retry] #{url} (#{e.class}), attempt #{attempt + 1}"
        sleep(1 + attempt)
        fetch_body(url, attempt: attempt + 1)
      else
        warn "  [skip] #{url} failed after #{MAX_RETRIES} retries: #{e.class}"
        nil
      end
    end
  end
end
