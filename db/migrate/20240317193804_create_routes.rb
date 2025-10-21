# frozen_string_literal: true

class CreateRoutes < ActiveRecord::Migration[7.0]
  def change
    create_table :routes do |t|
      t.references :waypoint_start, null: false, foreign_key: { to_table: :waypoints }
      t.references :waypoint_end, null: false, foreign_key: { to_table: :waypoints }
      t.jsonb :segments
      t.line_string :geom, srid: 4326, geographic: true

      t.timestamps
    end
  end
end
