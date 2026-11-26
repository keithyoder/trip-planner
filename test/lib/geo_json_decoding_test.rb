# frozen_string_literal: true

require 'test_helper'

# RGeo::GeoJSON parses strings through multi_json, so an incompatible pair of
# json and multi_json versions breaks network coverage and boundary imports
# while everything else keeps working. multi_json 1.21.1 did that with json 3.
class GeoJsonDecodingTest < ActiveSupport::TestCase
  test 'a GeoJSON string decodes to a geometry' do
    geometry = RGeo::GeoJSON.decode('{"type":"Point","coordinates":[-36.7,-8.4]}')

    assert_equal 'POINT (-36.7 -8.4)', geometry.as_text
  end
end
