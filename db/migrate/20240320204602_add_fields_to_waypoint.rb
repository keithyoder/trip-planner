class AddFieldsToWaypoint < ActiveRecord::Migration[7.0]
  def change
    add_column :waypoints, :type, :integer
    add_column :waypoints, :toll, :decimal
    add_column :waypoints, :delay, :integer
  end
end
