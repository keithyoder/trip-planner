# frozen_string_literal: true

require 'test_helper'

module OsmBoundaries
  class ImporterTest < ActiveSupport::TestCase
    # Stands in for the HTTP client: remembers what it was asked for and hands
    # back a one-feature collection shaped like osm-boundaries.com's (symbol keys).
    class FakeClient
      attr_reader :request

      def fetch_boundary(osm_id, level:, land_only:)
        @request = { osm_id: osm_id, level: level, land_only: land_only }
        ring = [[-58.0, 1.0], [-57.0, 1.0], [-57.0, 2.0], [-58.0, 1.0]]
        {
          type: 'FeatureCollection',
          features: [{
            type: 'Feature',
            geometry: { type: 'MultiPolygon', coordinates: [[ring]] },
            properties: { osm_id: osm_id, admin_level: level, name: 'Testland', name_en: 'Testland' }
          }]
        }
      end
    end

    setup { @client = FakeClient.new }

    def import(**options)
      capture_io { Importer.new(client: @client).fetch_and_import(-999_001, **options) }
      Boundary.find_by!(osm_id: -999_001)
    end

    test 'saves the boundary with its name, level, hierarchy and geometry' do
      boundary = import(level: 2, hierarchy_prefix: 'South_America')

      assert_equal ['Testland', 2, 'South_America.testland'], [boundary.name, boundary.level, boundary.hierarchy]
      assert_equal 1, boundary.geom.num_geometries
    end

    test 'importing the same OSM id again updates the row' do
      import(level: 2)

      assert_no_difference -> { Boundary.count } do
        import(level: 2)
      end
    end

    test 'asks for land-only outlines only when told to' do
      import(level: 2)
      assert_not @client.request[:land_only]

      import(level: 2, land_only: true)
      assert @client.request[:land_only]
    end
  end
end
