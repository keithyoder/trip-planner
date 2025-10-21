# frozen_string_literal: true

class CreateWaypoints < ActiveRecord::Migration[7.0]
  def change
    create_table :waypoints do |t|
      t.string :name
      t.string :address
      t.integer :sequence
      t.st_point :lonlat, srid: 4326, geographic: true

      t.timestamps
    end
  end
end
