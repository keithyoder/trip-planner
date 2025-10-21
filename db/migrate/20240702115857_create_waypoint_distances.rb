class CreateWaypointDistances < ActiveRecord::Migration[7.1]
  def change
    create_view :waypoint_distances
  end
end
