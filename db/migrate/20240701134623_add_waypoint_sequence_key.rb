class AddWaypointSequenceKey < ActiveRecord::Migration[7.1]
  def change
    add_index :waypoints, :sequence, unique: true
  end
end
