class ChangeType < ActiveRecord::Migration[7.1]
  def change
    rename_column :waypoints, :type, :waypoint_type
  end
end
