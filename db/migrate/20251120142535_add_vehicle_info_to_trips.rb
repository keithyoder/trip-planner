# frozen_string_literal: true

class AddVehicleInfoToTrips < ActiveRecord::Migration[7.2]
  def change
    add_column :trips, :vehicle_description, :string
    add_column :trips, :fuel_consumption_l_per_100km, :decimal, precision: 4, scale: 2
  end
end
