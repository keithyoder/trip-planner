class AddProfileToWaypoints < ActiveRecord::Migration[7.2]
  def change
    add_column :waypoints, :profile, :string, default: 'driving-car'
  end
end
