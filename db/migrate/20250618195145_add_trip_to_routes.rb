class AddTripToRoutes < ActiveRecord::Migration[7.1]
  def change
    add_reference :routes, :trip, null: true, foreign_key: true
    add_reference :waypoints, :trip, null: true, foreign_key: true
  end
end
