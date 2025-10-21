class CreateWaypointsBoundariesJoinTable < ActiveRecord::Migration[7.1]
  def change
    create_join_table :waypoints, :boundaries
  end
end
