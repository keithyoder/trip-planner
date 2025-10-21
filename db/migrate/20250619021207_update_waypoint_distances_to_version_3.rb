class UpdateWaypointDistancesToVersion3 < ActiveRecord::Migration[7.1]
  def change
    update_view :waypoint_distances, version: 3, revert_to_version: 2
  end
end
