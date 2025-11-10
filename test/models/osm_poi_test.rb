# frozen_string_literal: true

# == Schema Information
#
# Table name: osm_pois
#
#  id          :bigint           not null, primary key
#  name        :string
#  poi_type    :integer
#  city        :string
#  country     :string
#  district    :string
#  housenumber :string
#  milestone   :string
#  postcode    :string
#  province    :string
#  state       :string
#  street      :string
#  geom        :geography        point, 4326
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
require 'test_helper'

class OsmPoiTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
