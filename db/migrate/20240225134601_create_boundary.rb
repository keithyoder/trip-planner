# frozen_string_literal: true

class CreateBoundary < ActiveRecord::Migration[7.0]
  def change
    create_table :boundaries do |t|
      t.string :name
      t.integer :type
      t.multi_polygon :geom, srid: 4326, geographic: true

      t.timestamps
    end
  end
end
