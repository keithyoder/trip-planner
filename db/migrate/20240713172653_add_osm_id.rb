class AddOsmId < ActiveRecord::Migration[7.1]
  def change
    add_reference :waypoints, :osm_poi, index: true
  end
end
