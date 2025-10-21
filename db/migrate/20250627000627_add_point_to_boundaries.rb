class AddPointToBoundaries < ActiveRecord::Migration[7.1]
  def change
    add_column :boundaries, :admin_point, :st_point, geographic: true, null: true
    add_column :boundaries, :osm_id, :integer, null: true
    add_column :boundaries, :admin_node_id, :integer, null: true
  end
end
