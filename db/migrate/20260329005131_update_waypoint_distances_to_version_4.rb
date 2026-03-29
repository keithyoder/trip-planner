class UpdateWaypointDistancesToVersion4 < ActiveRecord::Migration[7.2]
  def change
    update_view :waypoint_distances, version: 4, revert_to_version: 3
  end
end
