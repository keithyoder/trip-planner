class ChangeUniqueIndex < ActiveRecord::Migration[7.1]
  def change
    remove_index :waypoints, name: "index_waypoints_on_sequence", if_exists: true
    add_index :waypoints, [:trip_id, :sequence], unique: true
  end
end
