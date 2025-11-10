# frozen_string_literal: true

# == Schema Information
#
# Table name: waypoints
#
#  id            :bigint           not null, primary key
#  name          :string
#  address       :string
#  sequence      :integer
#  lonlat        :geography        point, 4326
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  waypoint_type :integer
#  toll          :decimal(, )
#  delay         :integer
#  osm_poi_id    :bigint
#  trip_id       :bigint
#
require 'test_helper'

class WaypointTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
