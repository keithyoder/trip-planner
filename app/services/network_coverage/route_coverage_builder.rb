# frozen_string_literal: true

module NetworkCoverage
  # Given a single route (day/leg), figures out which country boundary(ies)
  # it actually passes through, fetches raw coverage features for each one
  # if we don't have them yet, and returns an array of buffered coverage
  # geometries (one per country crossed).
  #
  # Two consumers:
  #   - Trips::DayMapPdfRenderer, via Renderer::Map::CoverageOverlay, for the
  #     printed day-plan map (fetches eagerly if coverage data is missing --
  #     acceptable there since PDF generation is already a background job).
  #   - RoutesController#network_coverage, for the live Leaflet overlay on
  #     the route show page (built with fetch_if_missing: false, since a
  #     live HTTP request to a carrier's WMS/ArcGIS endpoint has no place
  #     blocking a page render -- see lib/tasks/coverage.rake for the
  #     out-of-band pre-fetch step that path depends on instead).
  #
  # Deliberately scoped per-route rather than per-trip: a route near a
  # border shouldn't drag in fetching coverage for a country the trip barely
  # touches, and a 120-day trip crossing 4+ countries means "just fetch
  # everything up front" would be wasteful and slow. The buffered union
  # itself is also computed against just this route's own line (not the
  # whole trip's track), since that's all a single day's map page needs.
  #
  # Usage (PDF path, eager fetch):
  #   builder = NetworkCoverage::RouteCoverageBuilder.new
  #   geometry = builder.build_for_route(route) # Array<RGeo geometry>
  #   Trips::DayMapPdfRenderer.new(route, coverage_geometry: geometry)
  #     .render_to_pdf.render_file('/tmp/day_map.pdf')
  #
  # Usage (live map path, never fetch):
  #   builder = NetworkCoverage::RouteCoverageBuilder.new(fetch_if_missing: false)
  #   geometries = builder.build_for_route(route) # [] if nothing pre-fetched yet
  #
  class RouteCoverageBuilder
    COUNTRY_LEVEL = 2 # OSM admin_level for countries, per Boundary#level
    PROVIDER = 'claro'

    # Which fetcher class pulls raw features for a country, and which
    # named provider layer to request. Countries not listed here are
    # silently skipped -- no known coverage source for them yet.
    COUNTRY_LAYERS = {
      'Uruguay' => { fetcher: NetworkCoverage::ClaroFetcher, layer: 'cobertura_externa_4G_UY' },
      'Chile' => { fetcher: NetworkCoverage::ChileFetcher, layer: 'cobertura_movil_4G_CL' },
      'Brasil' => { fetcher: NetworkCoverage::BrazilFetcher, layer: 'cobertura_movel_4G_BR' },
      'Perú' => { fetcher: NetworkCoverage::PeruFetcher, layer: 'cobertura_movil_4G_adicional_PE' }
    }.freeze

    # @param buffer_meters [Integer] passed through to NetworkCoverage::Union
    # @param fetch_if_missing [Boolean] whether #build_for_route may trigger
    #   a live fetch (Ensure_fetched) when a country/layer combo hasn't been
    #   fetched yet. true for the PDF/rake-task path; false for any
    #   request-cycle caller (see class doc above).
    def initialize(buffer_meters: NetworkCoverage::Union::DEFAULT_BUFFER_METERS, fetch_if_missing: true)
      @buffer_meters = buffer_meters
      # Union geometry per (route, boundary, layer) -- memoized per builder
      # instance so rendering a multi-day atlas that calls build_for_route
      # once per day doesn't recompute anything twice, though since the
      # union is now scoped to each route's own line rather than the whole
      # trip's track, there's little to actually share across routes;
      # this mainly guards against calling build_for_route on the same
      # route more than once.
      @union_cache = {}
      @fetch_if_missing = fetch_if_missing
    end

    # @param route [Route]
    # @param on_fetch_progress [Proc, nil] optional progress callback,
    #   forwarded to whichever country fetcher(s) actually need to run.
    #   Ignored entirely when fetch_if_missing: false.
    # @return [Array<RGeo::Feature::Geometry>] one buffered/clipped
    #   coverage geometry per country this route crosses -- may be shorter
    #   than the number of countries crossed (or empty) when
    #   fetch_if_missing: false and coverage hasn't been pre-fetched yet.
    def build_for_route(route, on_fetch_progress: nil)
      countries_for_route(route).filter_map do |boundary|
        config = COUNTRY_LAYERS[boundary.name]
        next unless config

        ensure_fetched(route, config, boundary, on_fetch_progress)
        cached_union_geometry(route, config, boundary)
      end
    end

    private

    # Countries this route's own geometry intersects, in the order the
    # route passes through them -- reuses the same ST_Intersects-based
    # scope already used elsewhere for per-leg boundary lookups.
    def countries_for_route(route)
      Boundary.intersecting_with_route(route.id).where(level: COUNTRY_LEVEL)
    end

    # Raw features are fetched/stored at the whole-trip/country level
    # (the *Fetcher classes sample the entire trip track) since that's
    # where the expensive, paginated API sampling happens -- not worth
    # re-running per day. route.trip.track gives the fetcher the full
    # trip line to sample against; only the union step afterward is
    # scoped down to this specific route's own geometry.
    #
    # No-ops entirely when fetch_if_missing: false, so the live-map request
    # path can never trigger a live carrier API call.
    def ensure_fetched(route, config, boundary, on_fetch_progress)
      return unless @fetch_if_missing

      already_fetched = NetworkCoverage::Feature.exists?(
        trip_id: route.trip_id, provider: PROVIDER, layer: config[:layer]
      )
      return if already_fetched

      fetcher = config[:fetcher].new(trip_track: route.trip.track, layer: config[:layer], boundary: boundary)
      on_fetch_progress ? fetcher.call(&on_fetch_progress) : fetcher.call
    end

    def cached_union_geometry(route, config, boundary)
      key = [route.id, boundary.id, config[:layer]]
      return @union_cache[key] if @union_cache.key?(key)

      @union_cache[key] = NetworkCoverage::Union.new(
        route: route,
        provider: PROVIDER,
        layer: config[:layer],
        boundary: boundary,
        buffer_meters: @buffer_meters
      ).call
    end
  end
end
